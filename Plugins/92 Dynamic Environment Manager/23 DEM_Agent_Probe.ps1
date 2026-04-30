# Start of Settings
# Operator hint: $Global:DEMAgentTarget = 'samplevdi.corp.local' (single FQDN, optional).
# Optional override: $Global:DEMAgentCredential = (Get-Credential).
# End of Settings

$Title          = 'DEM Agent Probe (Tier-2 PSRemoting)'
$Header         = 'FlexEngine agent state on a sample VDI'
$Comments       = @"
Connects via WinRM to the operator-supplied DEM Agent Probe Target (set on the DEM tab) and validates:
- FlexEngine.exe presence + file version
- VMware DEM Agent service install + Run state
- HKLM:\SOFTWARE\Policies\VMware, Inc.\Dynamic Environment Manager Agent registry keys (the GPO bind)
- ConfigShare path the agent currently believes it should pull from
- Last logon-task run timestamp from the DEM event log

This is the 'is the DEM agent actually doing what GPO told it to do' check. Without this, share-side validation can show OK while real users land on default-profile fallback.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P2'
$Recommendation = "If FlexEngine.exe is missing or service is Stopped, the user gets the local default profile. If the registry's ConfigShare value differs from the share you configured in this scan, GPO is pointing somewhere else - audit GPMC. Agent versions older than DEM 2306 lose support in 2025."

if (-not $Global:DEMAgentTarget) {
    [pscustomobject]@{ Note = 'No DEM Agent Probe Target configured. Set $Global:DEMAgentTarget OR fill the field on the DEM tab.' }
    return
}

$target = $Global:DEMAgentTarget
$cred = $Global:DEMAgentCredential
if (-not $cred) { $cred = $Global:HVImageScanCredential }

if (-not $cred) {
    [pscustomobject]@{ Target=$target; Note='No credential available. Set Deep-Scan Creds (top of GUI) or define $Global:DEMAgentCredential.' }
    return
}

# WinRM smoke test
$tcp = $false
try {
    $c = New-Object System.Net.Sockets.TcpClient
    $iar = $c.BeginConnect($target, 5985, $null, $null)
    if ($iar.AsyncWaitHandle.WaitOne(4000)) { $c.EndConnect($iar); $tcp = $true }
    $c.Close()
} catch { }
if (-not $tcp) {
    [pscustomobject]@{ Target=$target; Note='WinRM TCP/5985 unreachable from runner. Confirm firewall allows the runner machine to reach this VDI on 5985.' }
    return
}

$probeBlock = {
    $out = [ordered]@{
        FlexEngineExe   = ''
        FlexEngineVer   = ''
        ServiceName     = ''
        ServiceState    = ''
        RegConfigShare  = ''
        RegFlexEnable   = ''
        RegProfileShare = ''
        LastLogonTask   = ''
        EventErrorLast24h = 0
        Note            = ''
    }
    foreach ($p in @(
        'C:\Program Files\Immidio\Flex Profiles\FlexEngine.exe',
        'C:\Program Files\VMware\VMware DEM\FlexEngine.exe',
        'C:\Program Files\VMware\VMware DEM Enterprise\FlexEngine.exe',
        'C:\Program Files\Omnissa\Dynamic Environment Manager\FlexEngine.exe'
    )) {
        if (Test-Path $p) {
            $out.FlexEngineExe = $p
            try { $out.FlexEngineVer = (Get-Item $p).VersionInfo.FileVersion } catch { }
            break
        }
    }
    foreach ($svcName in @('vmwdem','VMware DEM Service','Immidio Flex Profiles Service','Omnissa DEM')) {
        $s = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($s) { $out.ServiceName = $s.Name; $out.ServiceState = [string]$s.Status; break }
    }
    $regPaths = @(
        'HKLM:\SOFTWARE\Policies\VMware, Inc.\Dynamic Environment Manager Agent',
        'HKLM:\SOFTWARE\Policies\Immidio\Flex Profiles',
        'HKLM:\SOFTWARE\Policies\Omnissa\Dynamic Environment Manager'
    )
    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            $r = Get-ItemProperty $rp -ErrorAction SilentlyContinue
            if ($r.FlexConfigPath) { $out.RegConfigShare = $r.FlexConfigPath }
            if ($r.ProfilePath)    { $out.RegProfileShare = $r.ProfilePath }
            $out.RegFlexEnable = if ($r.Enabled) { [string]$r.Enabled } else { '(default)' }
            break
        }
    }
    try {
        $log = Get-WinEvent -LogName Application -FilterHashtable @{ProviderName='FlexEngine'; StartTime=(Get-Date).AddHours(-24)} -ErrorAction SilentlyContinue -MaxEvents 200
        if ($log) {
            $latest = $log | Sort-Object TimeCreated -Descending | Select-Object -First 1
            $out.LastLogonTask = $latest.TimeCreated.ToString('yyyy-MM-dd HH:mm')
            $out.EventErrorLast24h = ($log | Where-Object Level -eq 2).Count
        }
    } catch { $out.Note = 'Event log read failed: ' + $_.Exception.Message }

    [pscustomobject]$out
}

try {
    $session = New-PSSession -ComputerName $target -Credential $cred -ErrorAction Stop
    $r = Invoke-Command -Session $session -ScriptBlock $probeBlock
    Remove-PSSession $session -ErrorAction SilentlyContinue

    [pscustomobject]@{
        Target              = $target
        FlexEngineExe       = $r.FlexEngineExe
        FlexEngineVersion   = $r.FlexEngineVer
        Service             = $r.ServiceName
        ServiceState        = $r.ServiceState
        GPO_ConfigShare     = $r.RegConfigShare
        GPO_ProfileShare    = $r.RegProfileShare
        GPO_AgentEnabled    = $r.RegFlexEnable
        LastLogonTaskRun    = $r.LastLogonTask
        AgentErrorsLast24h  = $r.EventErrorLast24h
        Note                = if ($Global:DEMConfigShare -and $r.RegConfigShare -and ($Global:DEMConfigShare -ne $r.RegConfigShare)) { "WARNING: GPO points at $($r.RegConfigShare), scan was given $($Global:DEMConfigShare). Mismatch." } else { $r.Note }
    }
} catch {
    [pscustomobject]@{
        Target = $target
        FlexEngineExe = '(probe failed)'
        Note = "WinRM probe failed: $($_.Exception.Message). Verify the credential has Remote Management Users membership on the target."
    }
}

$TableFormat = @{
    ServiceState = { param($v,$row) if ($v -eq 'Running') { 'ok' } elseif ($v -eq 'Stopped') { 'bad' } elseif ($v) { 'warn' } else { '' } }
    AgentErrorsLast24h = { param($v,$row) if ([int]"$v" -gt 0) { 'warn' } else { '' } }
    Note = { param($v,$row) if ($v -match 'WARNING|failed|Mismatch') { 'bad' } else { '' } }
}
