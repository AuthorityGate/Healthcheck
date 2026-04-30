#Requires -Version 5.1
<#
.SYNOPSIS
    End-to-end validation that a gold image is reachable for the deep-scan plugin.
    Walks through every step the plugin will use, reports pass/fail per step,
    and prints the exact remediation command when a step fails.

.DESCRIPTION
    Validation chain (each step must pass for the next to be meaningful):
      1. DNS resolution (if you supplied an FQDN)
      2. ICMP ping (best-effort - some images block, not fatal)
      3. TCP/5985 reachable (HTTP WinRM)
      4. TCP/5986 reachable (HTTPS WinRM, optional)
      5. Test-WSMan handshake
      6. Credential authenticates (New-PSSession)
      7. Probe scriptblock executes inside the guest (mirrors what the plugin does)

.PARAMETER Target
    IP address or FQDN of the gold image VM.

.PARAMETER Credential
    Windows credential. UPN form (user@domain) for domain accounts; .\\Administrator
    for local accounts on a non-domain-joined image. If omitted, you will be prompted.

.PARAMETER ProfileName
    OR: name of a saved AuthorityGate credential profile. Loads the credential
    via Get-AGCredentialAsPSCredential.

.EXAMPLE
    .\Tools\Test-GoldImageWinRM.ps1 -Target 10.69.101.179 -Credential (Get-Credential .\Administrator)

.EXAMPLE
    .\Tools\Test-GoldImageWinRM.ps1 -Target 10.69.101.179 -ProfileName 'Gold Image Local Admin'
#>
[CmdletBinding(DefaultParameterSetName='Direct')]
param(
    [Parameter(Mandatory)][string]$Target,
    [Parameter(ParameterSetName='Direct')][pscredential]$Credential,
    [Parameter(ParameterSetName='Profile')][string]$ProfileName
)

$ErrorActionPreference = 'Continue'

function Write-Step {
    param([string]$Step, [string]$Status, [string]$Detail='')
    $color = switch ($Status) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        'WARN' { 'Yellow' }
        default { 'White' }
    }
    $prefix = "[{0,-4}]" -f $Status
    Write-Host $prefix -ForegroundColor $color -NoNewline
    Write-Host " $Step" -NoNewline
    if ($Detail) { Write-Host "  $Detail" -ForegroundColor DarkGray }
    else { Write-Host '' }
}

function Write-Fix {
    param([string]$Cmd, [string]$Note='')
    if ($Note) { Write-Host "       $Note" -ForegroundColor Yellow }
    Write-Host "       Fix:  " -ForegroundColor Yellow -NoNewline
    Write-Host $Cmd -ForegroundColor Cyan
}

# Resolve credential
if ($ProfileName) {
    $modPath = Join-Path $PSScriptRoot '..\Modules\CredentialProfiles.psm1'
    if (-not (Test-Path $modPath)) {
        Write-Step "Resolve profile" "FAIL" "CredentialProfiles.psm1 not found at $modPath"
        return
    }
    Import-Module $modPath -Force
    try {
        $Credential = Get-AGCredentialAsPSCredential -Name $ProfileName
        Write-Step "Resolve profile" "PASS" "Profile '$ProfileName' loaded as $($Credential.UserName)"
    } catch {
        Write-Step "Resolve profile" "FAIL" $_.Exception.Message
        return
    }
} elseif (-not $Credential) {
    $Credential = Get-Credential -Message "Credential for $Target (use .\Administrator for non-domain templates, user@domain.com for domain)"
    if (-not $Credential) { Write-Host "Cancelled."; return }
}

Write-Host ""
Write-Host "=== Gold Image WinRM Validation ===" -ForegroundColor Cyan
Write-Host "Target:     $Target"
Write-Host "Credential: $($Credential.UserName)"
Write-Host ""

# 1. DNS / IP form
$ipPattern = '^(\d{1,3}\.){3}\d{1,3}$'
if ($Target -match $ipPattern) {
    Write-Step "1. Target is an IP address" "PASS" "DNS resolution skipped"
    $resolvedIp = $Target
} else {
    try {
        $r = [System.Net.Dns]::GetHostEntry($Target)
        $resolvedIp = $r.AddressList[0].IPAddressToString
        Write-Step "1. DNS resolution" "PASS" "$Target -> $resolvedIp"
    } catch {
        Write-Step "1. DNS resolution" "FAIL" $_.Exception.Message
        Write-Fix "nslookup $Target"
        Write-Fix "Add A record OR use IP directly"
        return
    }
}

# 2. ICMP ping (best effort)
try {
    $p = New-Object System.Net.NetworkInformation.Ping
    $reply = $p.Send($Target, 1500)
    if ($reply.Status -eq 'Success') {
        Write-Step "2. ICMP ping" "PASS" "RTT $($reply.RoundtripTime) ms"
    } else {
        Write-Step "2. ICMP ping" "WARN" "Status: $($reply.Status). Not fatal - many guests block ICMP."
    }
} catch {
    Write-Step "2. ICMP ping" "WARN" "Ping threw: $($_.Exception.Message). Continuing."
}

# 3. TCP/5985
$tcp5985 = $false
try {
    $t = New-Object System.Net.Sockets.TcpClient
    $async = $t.BeginConnect($Target, 5985, $null, $null)
    $tcp5985 = $async.AsyncWaitHandle.WaitOne(2000, $false) -and $t.Connected
    $t.Close()
} catch { }
if ($tcp5985) {
    Write-Step "3. TCP/5985 (WinRM HTTP)" "PASS"
} else {
    Write-Step "3. TCP/5985 (WinRM HTTP)" "FAIL"
    Write-Fix "On the gold image (or via VMware Tools console), run elevated:"
    Write-Fix "  Enable-PSRemoting -Force -SkipNetworkProfileCheck"
    Write-Fix "  New-NetFirewallRule -Name 'WinRM-HTTP-In-TCP' -DisplayName 'WinRM HTTP-In' -Profile Any -Protocol TCP -LocalPort 5985 -Action Allow"
    Write-Fix "  Set-NetFirewallProfile -Profile Any -DefaultInboundAction Allow  # if firewall is blocking"
}

# 4. TCP/5986 (optional)
$tcp5986 = $false
try {
    $t = New-Object System.Net.Sockets.TcpClient
    $async = $t.BeginConnect($Target, 5986, $null, $null)
    $tcp5986 = $async.AsyncWaitHandle.WaitOne(2000, $false) -and $t.Connected
    $t.Close()
} catch { }
if ($tcp5986) {
    Write-Step "4. TCP/5986 (WinRM HTTPS)" "PASS" "HTTPS listener available - more secure"
} else {
    Write-Step "4. TCP/5986 (WinRM HTTPS)" "WARN" "Not configured - HTTP/5985 is acceptable on a trusted lab network"
}

if (-not $tcp5985 -and -not $tcp5986) {
    Write-Host "`nStopping - no WinRM TCP path is open. Fix step 3 first." -ForegroundColor Red
    return
}

# 5. Test-WSMan
$wsmanOK = $false
try {
    $opts = @{ ComputerName = $Target; ErrorAction = 'Stop' }
    if (-not $tcp5986) { $opts.UseSSL = $false }
    Test-WSMan @opts | Out-Null
    Write-Step "5. Test-WSMan handshake" "PASS"
    $wsmanOK = $true
} catch {
    Write-Step "5. Test-WSMan handshake" "FAIL" $_.Exception.Message
    Write-Fix "On the runner workstation, add the target to TrustedHosts (NOT domain-joined OR HTTPS-not-used):"
    Write-Fix "  Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$Target' -Concatenate -Force"
    Write-Fix "OR enable HTTPS on the gold image to skip TrustedHosts:"
    Write-Fix "  winrm quickconfig -transport:https"
}

# 6. New-PSSession with credential
$session = $null
$pssessionOK = $false
try {
    $params = @{ ComputerName = $Target; Credential = $Credential; ErrorAction = 'Stop' }
    if (-not $tcp5986) { $params.Authentication = 'Negotiate' }
    $session = New-PSSession @params
    Write-Step "6. New-PSSession (auth)" "PASS" "Session ID $($session.Id) opened"
    $pssessionOK = $true
} catch {
    $msg = $_.Exception.Message
    Write-Step "6. New-PSSession (auth)" "FAIL" $msg
    if ($msg -match 'access is denied|user name or password is incorrect') {
        Write-Fix "Wrong username/password OR account lacks 'Allow log on through Remote Desktop' / 'Remote Management Users' rights."
        Write-Fix "Verify on the gold image: net localgroup 'Remote Management Users'"
        Write-Fix "Add user: net localgroup 'Remote Management Users' Administrator /add"
    } elseif ($msg -match 'WinRM cannot process|TrustedHosts') {
        Write-Fix "Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$Target' -Concatenate -Force"
        Write-Fix "OR use UPN form for domain accounts (user@authoritygate.net)"
    } elseif ($msg -match 'Negotiate') {
        Write-Fix "If using a local account on a non-domain VM, the user MUST be in form '.\Administrator' (with leading dot-backslash)."
    }
}

# 7. Probe scriptblock execution
if ($pssessionOK -and $session) {
    try {
        $probeResult = Invoke-Command -Session $session -ScriptBlock {
            $r = @{
                Hostname        = $env:COMPUTERNAME
                OsCaption       = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
                OsBuild         = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).BuildNumber
                IsDomainJoined  = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain
                Domain          = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Domain
                ToolsRunning    = $null -ne (Get-Service -Name 'VMTools' -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running')
                HorizonAgentVer = (Get-ItemProperty 'HKLM:\SOFTWARE\VMware, Inc.\VMware VDM\Agent' -ErrorAction SilentlyContinue).ProductVersion
                FSLogixEnabled  = [bool](Get-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue).Enabled
                DefenderRT      = -not (Get-MpPreference -ErrorAction SilentlyContinue).DisableRealtimeMonitoring
            }
            $r
        }
        Remove-PSSession $session
        Write-Step "7. In-guest probe" "PASS" "Plugin scriptblock executes correctly"
        Write-Host ""
        Write-Host "=== Probe results from $Target ===" -ForegroundColor Cyan
        $probeResult.GetEnumerator() | Sort-Object Name | ForEach-Object {
            Write-Host ("  {0,-18} = {1}" -f $_.Key, $_.Value)
        }
    } catch {
        Write-Step "7. In-guest probe" "FAIL" $_.Exception.Message
        Remove-PSSession $session -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "If all steps PASS, the deep-scan plugin will Tier 2 successfully against $Target."
Write-Host "If any FAIL, address the highlighted Fix line(s) before running the full health check."
