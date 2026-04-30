#Requires -Version 5.1
<#
    Licensing.psm1

    HealthCheckPS1 client-side licensing.

    Responsibilities:
        - Compute a stable machine fingerprint from HKLM\SOFTWARE\Microsoft\
          Cryptography\MachineGuid (SHA-256, namespace-salted).
        - Persist + read the license JWT at:
              %LOCALAPPDATA%\AuthorityGate\HorizonHealthCheck\license.jwt
        - Verify the license JWT offline against the embedded Ed25519 public
          key (no network call required to validate).
        - Build the deep-link URL to License.AuthorityGate.com/request that
          pre-fills the form with the operator's inputs.
        - Submit usage telemetry to /api/usage (Bearer-authed by the JWT).
        - Queue telemetry locally on network failure; flush on next run.

    The Ed25519 PUBLIC key was issued by the License.AuthorityGate.com
    deployment and is hard-coded below. Rotating it requires re-issuing
    every active license + shipping a new client.
#>

Set-StrictMode -Version Latest

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------

# Ed25519 public key, raw 32 bytes, base64-encoded. Generated 2026-04-28.
$Script:LicensePublicKeyB64 = 'gMZ3z+wsM7aMUZ5ABJlJ87ywjZJXQ6ZXp6frCtZOkgg='

# Production endpoint.
$Script:LicensePortalBase = 'https://license.authoritygate.com'

# Where the license file + telemetry queue live.
$Script:LicenseStoreFolder = $null   # populated lazily via Get-AGLicenseStorePath

# JWT issuer claim we accept.
$Script:ExpectedIssuer = 'license.authoritygate.com'

# Fingerprint salt - bumping this invalidates every issued license.
$Script:FingerprintSaltV1 = 'HCPS1-fp-v1|'


# --------------------------------------------------------------------------
# Storage helpers
# --------------------------------------------------------------------------

function Get-AGLicenseStorePath {
<#
    Returns the per-user folder where license + telemetry queue live.
    Idempotent: creates the folder if missing.
#>
    if (-not $Script:LicenseStoreFolder) {
        $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
        # Folder name kept stable across the v0.94.1 product rename so an
        # already-activated license + queued telemetry don't strand on upgrade.
        $Script:LicenseStoreFolder = Join-Path $base 'AuthorityGate\HorizonHealthCheck'
    }
    if (-not (Test-Path $Script:LicenseStoreFolder)) {
        New-Item -Path $Script:LicenseStoreFolder -ItemType Directory -Force | Out-Null
    }
    $Script:LicenseStoreFolder
}

function Get-AGLicenseFilePath {
    Join-Path (Get-AGLicenseStorePath) 'license.jwt'
}

function Get-AGUsageQueueFolder {
    $f = Join-Path (Get-AGLicenseStorePath) 'usage-queue'
    if (-not (Test-Path $f)) { New-Item -Path $f -ItemType Directory -Force | Out-Null }
    $f
}


# --------------------------------------------------------------------------
# Machine fingerprint
# --------------------------------------------------------------------------

function Get-AGFingerprintCachePath {
    Join-Path (Get-AGLicenseStorePath) 'machine-id.txt'
}

function Get-AGSha256Hex {
    # NOTE: parameter MUST NOT be named $Input (collides with PowerShell's
    # automatic $Input enumerable - subtle bug that produces wrong hashes
    # without any error).
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Script:FingerprintSaltV1 + $Text)
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
    -join ($hash | ForEach-Object { '{0:x2}' -f $_ })
}

function Get-AGFingerprintFromSources {
<#
    Returns @{ Source = '...'; Seed = '...' } for the FIRST source that
    produces a usable seed. Sources are tried in this fixed order:

      1. machine-guid     - HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid
                            (Windows-installed value; preferred)
      2. smbios-uuid      - SMBIOS / motherboard UUID via Win32_ComputerSystemProduct
      3. bios-serial+host - Win32_BIOS.SerialNumber concatenated with hostname
      4. generated-guid   - random GUID stored on first call; persists in cache file

    The Source name is part of the cache record so we never silently swap to
    a different algorithm on subsequent runs.
#>
    # 1. MachineGuid
    try {
        $rk = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop
        if ($rk.MachineGuid) { return @{ Source = 'machine-guid'; Seed = [string]$rk.MachineGuid } }
    } catch { }

    # 2. SMBIOS UUID
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop
        if ($cs.UUID -and $cs.UUID -ne 'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF' -and $cs.UUID -ne '00000000-0000-0000-0000-000000000000') {
            return @{ Source = 'smbios-uuid'; Seed = [string]$cs.UUID }
        }
    } catch { }

    # 3. BIOS serial + computer name
    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        if ($bios.SerialNumber -and $bios.SerialNumber.Trim() -and $bios.SerialNumber -notmatch '^(0+|[Tt]o [Bb]e [Ff]illed|System Serial Number|Default string)$') {
            return @{ Source = 'bios-serial-host'; Seed = "$($bios.SerialNumber)|$($env:COMPUTERNAME)" }
        }
    } catch { }

    # 4. Generated GUID (last resort) - persisted in the same cache file via
    #    a dedicated marker prefix so we know it was synthesized.
    return @{ Source = 'generated-guid'; Seed = [guid]::NewGuid().ToString() }
}

function Get-AGMachineFingerprint {
<#
    .SYNOPSIS
        Compute a stable, opaque, machine-bound identifier.

    .DESCRIPTION
        Tries multiple sources in priority order:
          1. HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid (preferred -
             Windows-installed value, rotates only on reinstall/sysprep).
          2. SMBIOS UUID (Win32_ComputerSystemProduct.UUID).
          3. BIOS serial + computer name (Win32_BIOS.SerialNumber + COMPUTERNAME).
          4. Generated GUID (last resort, persisted to disk so it stays stable).

        The first successful source wins. Once chosen, the resulting
        fingerprint is cached at:
            %LOCALAPPDATA%\AuthorityGate\HorizonHealthCheck\machine-id.txt
        Subsequent calls read the cache directly to guarantee the value is
        STABLE for the lifetime of the license - even if a higher-priority
        source becomes available later (e.g., MachineGuid restored), the
        cached value continues to be used so an issued license never
        becomes machine-mismatched.

        Salting (FingerprintSaltV1) prevents cross-referencing against
        unsalted MachineGuid lookups.

    .EXAMPLE
        Get-AGMachineFingerprint
        # -> 78543d5eb36a3b2a179c02dc7af3d24bc541ff46c7ee7ad01f4f107348a8e1fc

    .EXAMPLE
        # Diagnostic: print which source produced the fingerprint
        Get-AGMachineFingerprint -ShowSource

    .OUTPUTS
        Lowercase hex string, 64 chars.
#>
    [CmdletBinding()]
    param(
        [switch]$ShowSource,
        [switch]$NoCache       # diagnostic only - skip the cache file
    )

    $cachePath = Get-AGFingerprintCachePath

    # Cache hit: file exists with format "<source>|<fingerprint>"
    if (-not $NoCache -and (Test-Path $cachePath)) {
        try {
            $cached = (Get-Content -Raw -Path $cachePath).Trim()
            if ($cached -match '^([a-z0-9-]+)\|([a-f0-9]{64})$') {
                $src = $Matches[1]; $fp = $Matches[2]
                if ($ShowSource) { return [pscustomobject]@{ Source = $src; Fingerprint = $fp; FromCache = $true } }
                return $fp
            }
        } catch { }
    }

    # Compute fresh.
    #
    # IMPORTANT: backward compatibility. Pre-fallback releases hashed
    #   SHA256(salt + machineguid)
    # with no source-name prefix. A license issued before the fallback
    # change is bound to that hash. Keep the 'machine-guid' case using
    # the original input format so an existing license still validates;
    # only the new fallback sources (smbios-uuid, bios-serial-host,
    # generated-guid) include the source prefix in their hash input.
    $picked = Get-AGFingerprintFromSources
    $hashInput = if ($picked.Source -eq 'machine-guid') {
        $picked.Seed
    } else {
        "$($picked.Source)|$($picked.Seed)"
    }
    $fp = Get-AGSha256Hex -Text $hashInput
    if (-not $NoCache) {
        try { Set-Content -Path $cachePath -Value "$($picked.Source)|$fp" -Encoding ASCII -NoNewline } catch { }
    }

    if ($ShowSource) {
        return [pscustomobject]@{ Source = $picked.Source; Fingerprint = $fp; FromCache = $false }
    }
    return $fp
}

function Reset-AGMachineFingerprint {
<#
    .SYNOPSIS
        Wipe the cached fingerprint so the next Get-AGMachineFingerprint
        call re-derives it from the live system.

        WARNING: any active license bound to the previous fingerprint
        becomes machine-mismatched. Use only when intentionally
        re-keying the machine (e.g., hardware replaced).
#>
    [CmdletBinding()]
    param()
    $p = Get-AGFingerprintCachePath
    if (Test-Path $p) {
        Remove-Item -Path $p -Force
        Write-Host "Fingerprint cache cleared. Next call to Get-AGMachineFingerprint will re-derive from live system."
    } else {
        Write-Host "No fingerprint cache present at $p"
    }
}


# --------------------------------------------------------------------------
# JWT verification (Ed25519)
# --------------------------------------------------------------------------

function ConvertFrom-AGBase64Url {
    param([Parameter(Mandatory)][string]$Value)
    $pad = '=' * ((4 - ($Value.Length % 4)) % 4)
    $b64 = ($Value + $pad).Replace('-','+').Replace('_','/')
    [System.Convert]::FromBase64String($b64)
}

function ConvertTo-AGUtf8 {
    param([Parameter(Mandatory)][string]$Value)
    [System.Text.Encoding]::UTF8.GetBytes($Value)
}

function Test-AGEd25519Signature {
<#
    Verify an Ed25519 signature using the embedded public key. Returns $true
    if the signature is valid for the message.

    PowerShell 5.1 lacks native Ed25519. We import via System.Formats.Asn1 +
    System.Security.Cryptography.Ed25519 (available on .NET 6+ which ships
    with PowerShell 7.x). On 5.1, fall back to the bundled BouncyCastle.NET
    DLL if present, otherwise fail with a clear message.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$PublicKeyRaw32,
        [Parameter(Mandatory)][byte[]]$Message,
        [Parameter(Mandatory)][byte[]]$Signature
    )

    # Path A: .NET 6+ (Ed25519 in System.Security.Cryptography on PS7)
    $ed25519Type = [Type]::GetType('System.Security.Cryptography.Ed25519, System.Security.Cryptography')
    if ($ed25519Type) {
        $verifyMethod = $ed25519Type.GetMethod('Verify', [Type[]]@([byte[]],[byte[]],[byte[]]))
        if ($verifyMethod) {
            return [bool]$verifyMethod.Invoke($null, @($PublicKeyRaw32, $Message, $Signature))
        }
    }

    # Path B: BouncyCastle.NET (drop BouncyCastle.Cryptography.dll into the
    # script directory). Required for Windows PowerShell 5.1.
    try {
        Add-Type -AssemblyName 'BouncyCastle.Cryptography' -ErrorAction Stop
    } catch {
        try {
            $here = Split-Path -Parent $PSCommandPath
            $bc   = Join-Path $here 'BouncyCastle.Cryptography.dll'
            if (Test-Path $bc) {
                Add-Type -Path $bc -ErrorAction Stop
            } else {
                throw "BouncyCastle.Cryptography.dll not found beside Licensing.psm1 and PowerShell does not provide native Ed25519. Drop the DLL beside the module OR run with PowerShell 7+."
            }
        } catch {
            throw "Ed25519 verification unavailable: $($_.Exception.Message)"
        }
    }
    $params = [Org.BouncyCastle.Crypto.Parameters.Ed25519PublicKeyParameters]::new($PublicKeyRaw32, 0)
    $verifier = [Org.BouncyCastle.Crypto.Signers.Ed25519Signer]::new()
    $verifier.Init($false, $params)
    $verifier.BlockUpdate($Message, 0, $Message.Length)
    $verifier.VerifySignature($Signature)
}

function Test-AGLicenseToken {
<#
    .SYNOPSIS
        Validate a license JWT against the embedded public key + machine
        fingerprint + expiry.

    .OUTPUTS
        [pscustomobject]@{
            Valid        = $bool
            Reason       = $null | string   # populated on Valid=$false
            Claims       = $null | hashtable
            ExpiresAt    = $null | datetime
            MachineMatch = $bool
        }
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Token
    )

    $parts = $Token.Trim().Split('.')
    if ($parts.Count -ne 3) {
        return [pscustomobject]@{ Valid=$false; Reason='Token does not have 3 dot-separated parts'; Claims=$null; ExpiresAt=$null; MachineMatch=$false }
    }

    try {
        $headerJson  = [System.Text.Encoding]::UTF8.GetString((ConvertFrom-AGBase64Url $parts[0]))
        $payloadJson = [System.Text.Encoding]::UTF8.GetString((ConvertFrom-AGBase64Url $parts[1]))
        $sig         = ConvertFrom-AGBase64Url $parts[2]
    } catch {
        return [pscustomobject]@{ Valid=$false; Reason="Token parts are not valid base64url: $($_.Exception.Message)"; Claims=$null; ExpiresAt=$null; MachineMatch=$false }
    }

    $header = $headerJson  | ConvertFrom-Json
    $claims = $payloadJson | ConvertFrom-Json

    if ($header.alg -ne 'EdDSA') {
        return [pscustomobject]@{ Valid=$false; Reason="Unexpected JWT alg '$($header.alg)' (expected EdDSA)"; Claims=$claims; ExpiresAt=$null; MachineMatch=$false }
    }

    $pubKey  = ConvertFrom-AGBase64Url $Script:LicensePublicKeyB64
    $message = ConvertTo-AGUtf8 ("$($parts[0]).$($parts[1])")

    $sigOk = $false
    try { $sigOk = Test-AGEd25519Signature -PublicKeyRaw32 $pubKey -Message $message -Signature $sig } catch {
        return [pscustomobject]@{ Valid=$false; Reason="Signature verification failed: $($_.Exception.Message)"; Claims=$claims; ExpiresAt=$null; MachineMatch=$false }
    }
    if (-not $sigOk) {
        return [pscustomobject]@{ Valid=$false; Reason='Signature does not match public key'; Claims=$claims; ExpiresAt=$null; MachineMatch=$false }
    }

    if ($claims.iss -ne $Script:ExpectedIssuer) {
        return [pscustomobject]@{ Valid=$false; Reason="Issuer mismatch ('$($claims.iss)' != '$Script:ExpectedIssuer')"; Claims=$claims; ExpiresAt=$null; MachineMatch=$false }
    }

    $now    = [int][double]::Parse((Get-Date -UFormat %s))
    $expIso = (Get-Date '1970-01-01Z').AddSeconds([int]$claims.exp)
    if ([int]$claims.exp -le $now) {
        return [pscustomobject]@{ Valid=$false; Reason="Token expired at $expIso (UTC)"; Claims=$claims; ExpiresAt=$expIso; MachineMatch=$false }
    }

    $myFp = Get-AGMachineFingerprint
    $machineMatch = ($claims.machine -and ($claims.machine.ToString().ToLower() -eq $myFp.ToLower()))
    if (-not $machineMatch) {
        return [pscustomobject]@{ Valid=$false; Reason='License is bound to a different machine'; Claims=$claims; ExpiresAt=$expIso; MachineMatch=$false }
    }

    [pscustomobject]@{
        Valid        = $true
        Reason       = $null
        Claims       = $claims
        ExpiresAt    = $expIso
        MachineMatch = $true
    }
}


# --------------------------------------------------------------------------
# License file load / save
# --------------------------------------------------------------------------

function Get-AGLicense {
<#
    Read + validate the on-disk license. Returns the same shape as
    Test-AGLicenseToken, plus a TokenString. If no file exists, Valid=$false
    and Reason='No license file'.
#>
    [CmdletBinding()]
    param()
    $path = Get-AGLicenseFilePath
    if (-not (Test-Path $path)) {
        return [pscustomobject]@{ Valid=$false; Reason='No license file present (run the first-run wizard).'; Claims=$null; ExpiresAt=$null; MachineMatch=$false; TokenString=$null }
    }
    $tok = (Get-Content -Raw -Path $path).Trim()
    $r = Test-AGLicenseToken -Token $tok
    Add-Member -InputObject $r -NotePropertyName TokenString -NotePropertyValue $tok -Force
    $r
}

function Save-AGLicense {
<#
    Validate then persist a license JWT to disk. Throws on invalid.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Token
    )
    $clean = $Token -replace '\s+',''     # tolerate copy-paste with whitespace
    $r = Test-AGLicenseToken -Token $clean
    if (-not $r.Valid) {
        throw "License rejected: $($r.Reason)"
    }
    $path = Get-AGLicenseFilePath
    Set-Content -Path $path -Value $clean -Encoding ASCII -NoNewline
    $r
}


# --------------------------------------------------------------------------
# Deep-link builder (URL the GUI opens in the browser)
# --------------------------------------------------------------------------

function Get-AGRequestDeepLink {
<#
    .SYNOPSIS
        Build the License.AuthorityGate.com /request URL with all known
        fields pre-filled.

    .EXAMPLE
        Get-AGRequestDeepLink -Email 'me@x.com' -Engagement 'ACME-Q2' `
            -DocAuthor 'Jane Doe' -Company 'ACME' -Hostname $env:COMPUTERNAME
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Email,
        [string]$Engagement,
        [string]$DocAuthor,
        [string]$Company,
        [string]$Hostname = $env:COMPUTERNAME
    )
    # Belt-and-suspenders: even if Get-AGMachineFingerprint hits an exotic
    # failure mode (e.g., WMI service stopped on a hardened image so
    # Get-CimInstance throws AND HKLM is blocked AND BIOS unreadable), still
    # produce a deeplink with a generated GUID. The user gets a license bound
    # to that GUID; they can re-key later with Reset-AGMachineFingerprint.
    $fp = $null
    try { $fp = Get-AGMachineFingerprint } catch { }
    if (-not $fp -or $fp -notmatch '^[a-f0-9]{16,128}$') {
        $emergency = [guid]::NewGuid().ToString()
        $fp = Get-AGSha256Hex -Text "emergency-fallback|$emergency"
        try { Set-Content -Path (Get-AGFingerprintCachePath) -Value "emergency-fallback|$fp" -Encoding ASCII -NoNewline } catch { }
    }
    $q = New-Object System.Collections.Generic.List[string]
    $q.Add(('email='     + [System.Uri]::EscapeDataString($Email)))
    $q.Add(('fp='        + $fp))
    if ($Hostname)   { $q.Add(('hostname='   + [System.Uri]::EscapeDataString($Hostname))) }
    if ($Engagement) { $q.Add(('engagement=' + [System.Uri]::EscapeDataString($Engagement))) }
    if ($DocAuthor)  { $q.Add(('author='     + [System.Uri]::EscapeDataString($DocAuthor))) }
    if ($Company)    { $q.Add(('company='    + [System.Uri]::EscapeDataString($Company))) }
    "$Script:LicensePortalBase/request?" + ($q -join '&')
}


# --------------------------------------------------------------------------
# Telemetry submission
# --------------------------------------------------------------------------

function Submit-AGUsageEvent {
<#
    .SYNOPSIS
        POST a run telemetry event to /api/usage. Bearer-authed by the
        stored license JWT. On failure, persist the payload to the local
        queue for retry on the next successful POST.

    .PARAMETER Payload
        Hashtable matching the /api/usage shape:
        run_id, machine_fp, hostname, tool_version, started_at, completed_at,
        duration_seconds, doc_author, customer_engagement, targets[],
        plugin_count_total, plugin_count_executed, findings_summary,
        report_filename, report_size_bytes, status.

    .OUTPUTS
        @{ Submitted = $bool; Queued = $bool; Error = $null|string }
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Payload
    )

    $lic = Get-AGLicense
    if (-not $lic.Valid) {
        return @{ Submitted=$false; Queued=$false; Error="No valid license to authenticate telemetry: $($lic.Reason)" }
    }

    # Always set machine_fp from this machine - cannot be spoofed by caller.
    $Payload['machine_fp'] = Get-AGMachineFingerprint

    # PowerShell 5.1 ConvertTo-Json unwraps single-element arrays into objects.
    # Normalize so 'targets' always serializes as a JSON array - the server
    # validator (Zod) expects array shape and rejects with HTTP 400 otherwise.
    if ($Payload.ContainsKey('targets')) {
        $Payload['targets'] = @($Payload['targets'])
    }

    $body = $Payload | ConvertTo-Json -Depth 10 -Compress
    $headers = @{
        Authorization  = "Bearer $($lic.TokenString)"
        'Content-Type' = 'application/json'
    }
    try {
        $r = Invoke-WebRequest -Uri "$Script:LicensePortalBase/api/usage" -Method Post -Body $body -Headers $headers -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) {
            return @{ Submitted=$true; Queued=$false; Error=$null }
        }
        $err = "HTTP $($r.StatusCode): $($r.Content)"
    } catch {
        # Try to extract the JSON body from the WebException so we see the
        # server-side validation detail instead of just '400 Bad Request'.
        $err = $_.Exception.Message
        try {
            $resp = $_.Exception.Response
            if ($resp -and $resp.GetResponseStream) {
                $stream = $resp.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $rawBody = $reader.ReadToEnd()
                $reader.Close()
                if ($rawBody) {
                    $err = "HTTP $([int]$resp.StatusCode): $rawBody"
                }
            }
        } catch { }
    }

    # Queue locally
    try {
        $queueDir = Get-AGUsageQueueFolder
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
        $file = Join-Path $queueDir "usage-$stamp-$([guid]::NewGuid().ToString('N').Substring(0,8)).json"
        Set-Content -Path $file -Value $body -Encoding UTF8 -NoNewline
        return @{ Submitted=$false; Queued=$true; Error=$err }
    } catch {
        return @{ Submitted=$false; Queued=$false; Error="$err ; Queue write also failed: $($_.Exception.Message)" }
    }
}

function Submit-AGUsageQueue {
<#
    Drain the local usage queue. Called at start of a run.
    Returns @{ Drained = <int>; Remaining = <int> }.
#>
    [CmdletBinding()]
    param()
    $queueDir = Get-AGUsageQueueFolder
    $files = @(Get-ChildItem -Path $queueDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    if ($files.Count -eq 0) { return @{ Drained=0; Remaining=0 } }

    $lic = Get-AGLicense
    if (-not $lic.Valid) { return @{ Drained=0; Remaining=$files.Count } }

    $drained = 0
    foreach ($f in $files) {
        try {
            $body = Get-Content -Raw -Path $f.FullName
            $headers = @{
                Authorization  = "Bearer $($lic.TokenString)"
                'Content-Type' = 'application/json'
            }
            $r = Invoke-WebRequest -Uri "$Script:LicensePortalBase/api/usage" -Method Post -Body $body -Headers $headers -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) {
                Remove-Item -Path $f.FullName -Force
                $drained++
            }
        } catch {
            # Stop on first failure - the queue stays for the next run.
            break
        }
    }
    @{ Drained=$drained; Remaining=(@(Get-ChildItem -Path $queueDir -Filter '*.json' -File -ErrorAction SilentlyContinue).Count) }
}


# --------------------------------------------------------------------------
# Public surface
# --------------------------------------------------------------------------

Export-ModuleMember -Function `
    Get-AGMachineFingerprint, `
    Reset-AGMachineFingerprint, `
    Get-AGFingerprintCachePath, `
    Get-AGLicenseStorePath, `
    Get-AGLicenseFilePath, `
    Get-AGUsageQueueFolder, `
    Get-AGLicense, `
    Save-AGLicense, `
    Test-AGLicenseToken, `
    Get-AGRequestDeepLink, `
    Submit-AGUsageEvent, `
    Submit-AGUsageQueue
