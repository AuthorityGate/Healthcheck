#Requires -Version 5.1
<#
    CredentialProfiles.psm1

    Centralized named-credential store for the AuthorityGate HealthCheck
    runner. One credential profile = one (Name, UserName, Password, Type, Notes)
    record. Passwords are stored DPAPI-encrypted via PowerShell's native
    ConvertFrom-SecureString, which means:
      - The encrypted blob is bound to the current Windows user account on
        the current machine. Another user (or another machine) cannot
        decrypt it. This is the right model for per-operator credential
        storage.
      - No third-party encryption library required. Pure PowerShell.

    Storage location:
        $env:LOCALAPPDATA\AuthorityGate\HorizonHealthCheck\credentials.xml

    Profile schema (one entry):
        Name            : 'AuthorityGate Domain Admin'        (unique key)
        UserName        : 'administrator@authoritygate.net'   (raw text)
        EncryptedPwd    : '<DPAPI ciphertext blob>'           (string)
        Type            : 'Domain'  | 'Local' | 'vCenterSSO' | 'API' | 'Other'
        Notes           : free-form text the operator can use to identify intent
        Created         : 'yyyy-MM-dd HH:mm:ss'
        LastUsed        : 'yyyy-MM-dd HH:mm:ss'

    Public API:
        Get-AGCredentialProfile [-Name <name>]       - list all, or fetch one
        Set-AGCredentialProfile -Name -Credential -Type [-Notes]   - upsert
        Remove-AGCredentialProfile -Name             - delete
        Get-AGCredentialAsPSCredential -Name         - return as [pscredential]
        Test-AGCredentialProfile -Name -Target -Mode - validate (optional)
        Export-AGCredentialProfiles -Path -Passphrase  - portable export
        Import-AGCredentialProfiles -Path -Passphrase  - portable import
        Get-AGCredentialProfileStorePath             - resolve current path
#>

Set-StrictMode -Version Latest

$Script:CredStoreFolder = $null
$Script:CredStoreFile   = $null
$Script:CredStoreCache  = $null   # In-memory hashtable, keyed by Name

function Initialize-AGCredentialStore {
<#
    Resolves the per-user store folder + file. Creates the directory if missing.
    Loads existing profiles into the cache. Idempotent.
#>
    [CmdletBinding()]
    param(
        [string]$OverrideFolder
    )
    if ($OverrideFolder) {
        $Script:CredStoreFolder = $OverrideFolder
    } else {
        $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
        # Folder name kept stable across the v0.94.1 product rename
        # (HorizonHealthCheck -> AuthorityGate HealthCheck) so existing
        # DPAPI-encrypted credentials don't strand on upgrade. Renaming the
        # folder would force every operator to re-enter every saved cred.
        $Script:CredStoreFolder = Join-Path $base 'AuthorityGate\HorizonHealthCheck'
    }
    $Script:CredStoreFile = Join-Path $Script:CredStoreFolder 'credentials.xml'

    if (-not (Test-Path $Script:CredStoreFolder)) {
        New-Item -Path $Script:CredStoreFolder -ItemType Directory -Force | Out-Null
    }

    $Script:CredStoreCache = [ordered]@{}
    if (Test-Path $Script:CredStoreFile) {
        try {
            $loaded = Import-Clixml -Path $Script:CredStoreFile -ErrorAction Stop
            if ($loaded -is [System.Collections.IDictionary]) {
                foreach ($k in $loaded.Keys) { $Script:CredStoreCache[$k] = $loaded[$k] }
            } elseif ($loaded -is [array]) {
                foreach ($p in $loaded) { if ($p.Name) { $Script:CredStoreCache[$p.Name] = $p } }
            }
        } catch {
            Write-Warning "Could not load credential store at $($Script:CredStoreFile): $($_.Exception.Message). Starting with empty cache."
        }
    }
}

function Get-AGCredentialProfileStorePath {
    if (-not $Script:CredStoreFile) { Initialize-AGCredentialStore }
    $Script:CredStoreFile
}

function Save-AGCredentialStore {
    # Internal - persist the in-memory cache to disk.
    if (-not $Script:CredStoreCache) { Initialize-AGCredentialStore }
    # Convert OrderedDictionary to array of PSCustomObject for cleaner Clixml.
    $arr = @()
    foreach ($k in $Script:CredStoreCache.Keys) { $arr += $Script:CredStoreCache[$k] }
    $arr | Export-Clixml -Path $Script:CredStoreFile -Encoding UTF8 -Force
}

function Get-AGCredentialProfile {
<#
    .SYNOPSIS
    Returns one or all stored credential profiles.

    .EXAMPLE
    Get-AGCredentialProfile                    # list all
    Get-AGCredentialProfile -Name 'Lab Admin'  # specific profile
#>
    [CmdletBinding()]
    param([string]$Name)
    if (-not $Script:CredStoreCache) { Initialize-AGCredentialStore }
    if ($Name) {
        if ($Script:CredStoreCache.Contains($Name)) { return $Script:CredStoreCache[$Name] }
        return $null
    }
    @($Script:CredStoreCache.Values)
}

function Set-AGCredentialProfile {
<#
    .SYNOPSIS
    Create or update a credential profile.

    .PARAMETER Name
    Unique label - used as the lookup key. Re-using a Name overwrites.

    .PARAMETER Credential
    A standard [pscredential]. The password is extracted, encrypted via
    DPAPI (per-user, per-machine) and stored as an opaque string.

    .PARAMETER Type
    Free-tag classification - 'Domain' | 'Local' | 'vCenterSSO' | 'API' |
    'Other'. Helps the GUI suggest profiles in the right context (e.g.,
    show 'Local' profiles for gold-image WinRM, 'Domain' for AD scans).

    .PARAMETER Notes
    Operator-facing description shown in the GUI list.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][pscredential]$Credential,
        [ValidateSet('Domain','Local','vCenterSSO','API','Other')][string]$Type = 'Other',
        [string]$Notes
    )
    if (-not $Script:CredStoreCache) { Initialize-AGCredentialStore }

    # ConvertFrom-SecureString uses DPAPI by default on Windows PowerShell 5.1
    # and PowerShell 7+ on Windows. Result: opaque string bound to current user
    # + machine.
    $encPwd = $Credential.Password | ConvertFrom-SecureString

    $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $existing = if ($Script:CredStoreCache.Contains($Name)) { $Script:CredStoreCache[$Name] } else { $null }
    $created = if ($existing) { $existing.Created } else { $now }

    $profile = [pscustomobject]@{
        Name         = $Name
        UserName     = $Credential.UserName
        EncryptedPwd = $encPwd
        Type         = $Type
        Notes        = $Notes
        Created      = $created
        LastUsed     = $now
    }
    $Script:CredStoreCache[$Name] = $profile
    Save-AGCredentialStore
    $profile
}

function Remove-AGCredentialProfile {
<#
    .SYNOPSIS
    Delete a credential profile by name.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name
    )
    if (-not $Script:CredStoreCache) { Initialize-AGCredentialStore }
    if ($Script:CredStoreCache.Contains($Name)) {
        $Script:CredStoreCache.Remove($Name)
        Save-AGCredentialStore
        $true
    } else { $false }
}

function Get-AGCredentialAsPSCredential {
<#
    .SYNOPSIS
    Resolve a stored profile back to a usable [pscredential]. The password
    is decrypted from DPAPI on demand. The returned object can be passed to
    Connect-VIServer / Connect-HVRest / Invoke-Command / etc.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name
    )
    $p = Get-AGCredentialProfile -Name $Name
    if (-not $p) { throw "Credential profile '$Name' not found." }
    try {
        $sec = ConvertTo-SecureString $p.EncryptedPwd -ErrorAction Stop
    } catch {
        throw "Credential profile '$Name' could not be decrypted on this machine. DPAPI ties the encrypted blob to the user/machine that created it. If the profile was created on a different machine or by a different Windows user, it is unreadable here. Re-create the profile or import an exported file."
    }
    # Update LastUsed
    $p.LastUsed = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $Script:CredStoreCache[$Name] = $p
    Save-AGCredentialStore
    New-Object System.Management.Automation.PSCredential ($p.UserName, $sec)
}

function Test-AGCredentialProfile {
<#
    .SYNOPSIS
    Validate a profile against a target endpoint. Returns @{ OK; Message }.
    Lightweight - tries a CIM/WinRM session for Local/Domain creds, or a
    plain Connect-VIServer for vCenterSSO type.

    .PARAMETER Mode
    'WinRM'    - Test-WSMan + temporary New-CimSession
    'vCenter'  - Connect-VIServer (then disconnect)
    'AD'       - Get-ADForest -Server $Target
    'TCP'      - just a TCP probe to a chosen port
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Target,
        [ValidateSet('WinRM','vCenter','AD','TCP')][string]$Mode = 'WinRM',
        [int]$TcpPort = 443
    )
    $cred = Get-AGCredentialAsPSCredential -Name $Name
    switch ($Mode) {
        'WinRM' {
            try {
                $s = New-CimSession -ComputerName $Target -Credential $cred -ErrorAction Stop
                Remove-CimSession $s
                @{ OK = $true; Message = "WinRM/CIM auth succeeded against $Target." }
            } catch { @{ OK = $false; Message = $_.Exception.Message } }
        }
        'vCenter' {
            try {
                Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
                $vi = Connect-VIServer -Server $Target -Credential $cred -ErrorAction Stop -Force
                Disconnect-VIServer -Server $vi -Confirm:$false -Force | Out-Null
                @{ OK = $true; Message = "vCenter auth succeeded against $Target." }
            } catch { @{ OK = $false; Message = $_.Exception.Message } }
        }
        'AD' {
            try {
                Import-Module ActiveDirectory -ErrorAction Stop
                $forest = Get-ADForest -Server $Target -Credential $cred -ErrorAction Stop
                @{ OK = $true; Message = "AD auth succeeded - forest: $($forest.Name)" }
            } catch { @{ OK = $false; Message = $_.Exception.Message } }
        }
        'TCP' {
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $async = $tcp.BeginConnect($Target, $TcpPort, $null, $null)
                $ok = $async.AsyncWaitHandle.WaitOne(2000, $false) -and $tcp.Connected
                $tcp.Close()
                @{ OK = $ok; Message = if ($ok) { "TCP $Target`:$TcpPort reachable" } else { "TCP $Target`:$TcpPort unreachable" } }
            } catch { @{ OK = $false; Message = $_.Exception.Message } }
        }
    }
}

function Export-AGCredentialProfiles {
<#
    .SYNOPSIS
    Export profiles to a portable file using a passphrase. Re-encrypts the
    DPAPI-protected passwords with AES-256 keyed off the passphrase, so the
    file can move to another machine / another user.

    .PARAMETER Path
    Output file path.

    .PARAMETER Passphrase
    SecureString passphrase used to derive the AES key (PBKDF2).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][SecureString]$Passphrase
    )
    if (-not $Script:CredStoreCache) { Initialize-AGCredentialStore }
    if ($Script:CredStoreCache.Count -eq 0) {
        throw "Credential store is empty - nothing to export."
    }

    # Derive an AES key + IV from the passphrase via PBKDF2.
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Passphrase)
    $passText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null

    $salt = New-Object byte[] 16
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
    $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes ($passText, $salt, 100000, 'SHA256')
    $keyBytes = $kdf.GetBytes(32)
    $ivBytes  = $kdf.GetBytes(16)
    $kdf.Dispose()

    $portable = @()
    foreach ($k in $Script:CredStoreCache.Keys) {
        $p = $Script:CredStoreCache[$k]
        # Decrypt DPAPI password to plaintext, then re-encrypt with AES.
        try {
            $sec = ConvertTo-SecureString $p.EncryptedPwd -ErrorAction Stop
            $b = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) | Out-Null
        } catch {
            Write-Warning "Skipping '$k' - DPAPI decrypt failed: $($_.Exception.Message)"
            continue
        }

        $aes = [Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes
        $aes.IV  = $ivBytes
        $enc = $aes.CreateEncryptor()
        $plainBytes = [Text.Encoding]::UTF8.GetBytes($plain)
        $cipherBytes = $enc.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
        $aes.Dispose()

        $portable += [pscustomobject]@{
            Name      = $p.Name
            UserName  = $p.UserName
            CipherB64 = [Convert]::ToBase64String($cipherBytes)
            Type      = $p.Type
            Notes     = $p.Notes
            Created   = $p.Created
        }
    }

    $bundle = [pscustomobject]@{
        Schema   = 'AGCredentialProfiles/1'
        Exported = (Get-Date).ToString('o')
        SaltB64  = [Convert]::ToBase64String($salt)
        Profiles = $portable
    }
    $bundle | ConvertTo-Json -Depth 5 | Out-File -FilePath $Path -Encoding utf8
    Write-Host "[+] Exported $($portable.Count) profile(s) to $Path"
}

function Import-AGCredentialProfiles {
<#
    .SYNOPSIS
    Import profiles previously exported with Export-AGCredentialProfiles.
    Re-encrypts each password with the local machine's DPAPI on import.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][SecureString]$Passphrase,
        [switch]$Overwrite
    )
    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    if (-not $Script:CredStoreCache) { Initialize-AGCredentialStore }

    $bundle = Get-Content $Path -Raw | ConvertFrom-Json
    if ($bundle.Schema -ne 'AGCredentialProfiles/1') { throw "Unexpected schema '$($bundle.Schema)'." }

    $salt = [Convert]::FromBase64String($bundle.SaltB64)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Passphrase)
    $passText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
    $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes ($passText, $salt, 100000, 'SHA256')
    $keyBytes = $kdf.GetBytes(32); $ivBytes = $kdf.GetBytes(16); $kdf.Dispose()

    $count = 0
    foreach ($p in @($bundle.Profiles)) {
        if ($Script:CredStoreCache.Contains($p.Name) -and -not $Overwrite) {
            Write-Warning "Profile '$($p.Name)' exists - skipping (pass -Overwrite to replace)."
            continue
        }
        $aes = [Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes; $aes.IV = $ivBytes
        $dec = $aes.CreateDecryptor()
        try {
            $cipher = [Convert]::FromBase64String($p.CipherB64)
            $plainBytes = $dec.TransformFinalBlock($cipher, 0, $cipher.Length)
            $plain = [Text.Encoding]::UTF8.GetString($plainBytes)
        } catch {
            Write-Warning "Decrypt failed for '$($p.Name)' - wrong passphrase?"
            $aes.Dispose(); continue
        }
        $aes.Dispose()

        $sec = ConvertTo-SecureString $plain -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($p.UserName, $sec)
        Set-AGCredentialProfile -Name $p.Name -Credential $cred -Type $p.Type -Notes $p.Notes | Out-Null
        $count++
    }
    Write-Host "[+] Imported $count profile(s) from $Path"
}

# Initialize on module load so the path + cache are ready
Initialize-AGCredentialStore

Export-ModuleMember -Function `
    Get-AGCredentialProfile, Set-AGCredentialProfile, Remove-AGCredentialProfile, `
    Get-AGCredentialAsPSCredential, Test-AGCredentialProfile, `
    Export-AGCredentialProfiles, Import-AGCredentialProfiles, `
    Get-AGCredentialProfileStorePath, Initialize-AGCredentialStore
