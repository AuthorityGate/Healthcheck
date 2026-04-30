# Start of Settings
# Operator hint: $Global:FSLogixAgentTarget = 'samplevdi.corp.local'
# End of Settings

$Title          = "FSLogix Agent Probe"
$Header         = "FSLogix agent state on a sample VDI"
$Comments       = "PSRemoting probe to a sample VDI machine. Reads HKLM:\SOFTWARE\FSLogix policy registry (the GPO bind), service state, agent file version, last-mount errors from the FSLogix-Apps event log."
$Display        = "List"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B8 FSLogix"
$Severity       = "P2"
$Recommendation = "If agent service is Stopped or registry shows Enabled=0, users land on local profile. Agent versions older than 2.9.x lose support. Recurring 'failed to mount VHD' events = share / ACL / disk-corruption issue."

if (-not $Global:FSLogixAgentTarget) {
    [pscustomobject]@{ Note = 'No FSLogix Agent Probe Target configured. Set $Global:FSLogixAgentTarget OR via Specialized Scope.' }
    return
}
$target = $Global:FSLogixAgentTarget
$cred = $Global:FSLogixAgentCredential
if (-not $cred) { $cred = $Global:HVImageScanCredential }
if (-not $cred) {
    [pscustomobject]@{ Target=$target; Note='No credential available. Set Deep-Scan Creds (top of GUI) or define $Global:FSLogixAgentCredential.' }
    return
}

$probeBlock = {
    $out = [ordered]@{
        AgentExe        = ''
        AgentVer        = ''
        ServiceName     = ''
        ServiceState    = ''
        RegEnabled      = ''
        RegVHDLocations = ''
        RegFlipFlopProfileDirectoryName = ''
        RegSizeInMBs    = ''
        EventErrorLast24h = 0
        Note            = ''
    }
    foreach ($p in @('C:\Program Files\FSLogix\Apps\frx.exe','C:\Program Files\FSLogix\Apps\frxccd.exe')) {
        if (Test-Path $p) {
            $out.AgentExe = $p
            try { $out.AgentVer = (Get-Item $p).VersionInfo.FileVersion } catch { }
            break
        }
    }
    foreach ($svc in @('frxsvc','frxccds','FSLogix Apps')) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) { $out.ServiceName = $s.Name; $out.ServiceState = [string]$s.Status; break }
    }
    if (Test-Path 'HKLM:\SOFTWARE\FSLogix\Profiles') {
        $r = Get-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue
        $out.RegEnabled                       = [string]$r.Enabled
        $out.RegVHDLocations                  = ($r.VHDLocations -join '; ')
        $out.RegFlipFlopProfileDirectoryName = [string]$r.FlipFlopProfileDirectoryName
        $out.RegSizeInMBs                     = [string]$r.SizeInMBs
    }
    try {
        $log = Get-WinEvent -LogName 'Microsoft-FSLogix-Apps/Operational' -MaxEvents 200 -ErrorAction SilentlyContinue |
               Where-Object { $_.TimeCreated -gt (Get-Date).AddHours(-24) }
        if ($log) {
            $out.EventErrorLast24h = ($log | Where-Object Level -eq 2).Count
        }
    } catch { $out.Note = 'Event log read failed: ' + $_.Exception.Message }
    [pscustomobject]$out
}

$tcp = $false
try {
    $c = New-Object System.Net.Sockets.TcpClient
    $iar = $c.BeginConnect($target, 5985, $null, $null)
    if ($iar.AsyncWaitHandle.WaitOne(4000)) { $c.EndConnect($iar); $tcp = $true }
    $c.Close()
} catch { }
if (-not $tcp) {
    [pscustomobject]@{ Target=$target; Note='WinRM TCP/5985 unreachable from runner.' }
    return
}

try {
    $session = New-PSSession -ComputerName $target -Credential $cred -ErrorAction Stop
    $r = Invoke-Command -Session $session -ScriptBlock $probeBlock
    Remove-PSSession $session -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Target          = $target
        AgentExe        = $r.AgentExe
        AgentVersion    = $r.AgentVer
        Service         = $r.ServiceName
        ServiceState    = $r.ServiceState
        Reg_Enabled     = $r.RegEnabled
        Reg_VHDLocations = $r.RegVHDLocations
        Reg_FlipFlop    = $r.RegFlipFlopProfileDirectoryName
        Reg_SizeMB      = $r.RegSizeInMBs
        AgentErrorsLast24h = $r.EventErrorLast24h
        Note            = $r.Note
    }
} catch {
    [pscustomobject]@{ Target=$target; Note="WinRM probe failed: $($_.Exception.Message)" }
}

$TableFormat = @{
    ServiceState = { param($v,$row) if ($v -eq 'Running') { 'ok' } elseif ($v -eq 'Stopped') { 'bad' } elseif ($v) { 'warn' } else { '' } }
    Reg_Enabled  = { param($v,$row) if ($v -eq '1') { 'ok' } elseif ($v -eq '0') { 'bad' } else { '' } }
    AgentErrorsLast24h = { param($v,$row) if ([int]"$v" -gt 0) { 'warn' } else { '' } }
}
