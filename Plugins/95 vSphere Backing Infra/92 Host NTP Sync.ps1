# Start of Settings
# Maximum tolerable clock skew (seconds) before a row is flagged.
$MaxClockSkewSeconds = 60
# End of Settings

$Title          = "ESXi NTP Service / Clock Skew"
$Header         = "Per-host NTP service state, configured servers, and skew"
$Comments       = "VMware KB 57147 / 1339: Horizon authentication uses Kerberos which fails with > 5 minutes clock drift. We flag at 60 s as an early warning. Two NTP sources minimum are recommended. Lists every host regardless of state so operators can verify the check ran."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = "95 vSphere Backing Infra"
$Severity       = "P1"
$Recommendation = "Set 'ntpd' service to Start automatically, configure 2+ NTP sources, then 'Restart NTP Daemon'. Verify with 'esxcli system time get' (KB 57147)."

if (-not $Global:VCConnected) { return }

$hosts = @(Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Note='Get-VMHost returned no hosts.' }
    return
}

foreach ($h in $hosts) {
    $ntpSvc   = Get-VMHostService -VMHost $h -ErrorAction SilentlyContinue | Where-Object { $_.Key -eq 'ntpd' }
    $ntpHosts = @(Get-VMHostNtpServer -VMHost $h -ErrorAction SilentlyContinue)
    $ntpStr   = ($ntpHosts -join ', ')
    $vcTime   = (Get-Date).ToUniversalTime()
    $hostTime = $null
    try { $hostTime = $h.ExtensionData.RetrieveDateTime() } catch { }
    $skew = if ($hostTime) { [int][math]::Abs(($hostTime - $vcTime).TotalSeconds) } else { $null }

    $running = if ($ntpSvc) { [bool]$ntpSvc.Running } else { $false }
    $policy  = if ($ntpSvc) { "$($ntpSvc.Policy)" } else { 'n/a' }
    $issues = @()
    if (-not $ntpSvc)               { $issues += 'no ntpd' }
    elseif (-not $running)          { $issues += 'not running' }
    if ($policy -ne 'on')           { $issues += "policy=$policy" }
    if ($ntpHosts.Count -eq 0)      { $issues += 'no servers' }
    elseif ($ntpHosts.Count -lt 2)  { $issues += 'only 1 server' }
    if ($skew -ne $null -and $skew -gt $MaxClockSkewSeconds) { $issues += "skew>${MaxClockSkewSeconds}s" }

    $status = if ($issues.Count -eq 0) { 'OK' } else { ($issues -join '; ') }

    [pscustomobject]@{
        Host         = $h.Name
        Cluster      = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
        NTPRunning   = $running
        NTPPolicy    = $policy
        NTPServers   = if ($ntpStr) { $ntpStr } else { '(none)' }
        ServerCount  = $ntpHosts.Count
        ClockSkewSec = if ($null -ne $skew) { $skew } else { 'unknown' }
        Status       = $status
    }
}

$TableFormat = @{
    NTPRunning   = { param($v,$row) if ($v -eq $false) { 'bad' } else { '' } }
    NTPPolicy    = { param($v,$row) if ("$v" -ne 'on') { 'warn' } else { '' } }
    NTPServers   = { param($v,$row) if ("$v" -eq '(none)') { 'bad' } else { '' } }
    ServerCount  = { param($v,$row) if ([int]"$v" -lt 2) { 'warn' } else { '' } }
    ClockSkewSec = { param($v,$row) if ("$v" -match '^\d+$' -and [int]"$v" -gt 60) { 'bad' } else { '' } }
    Status       = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } else { 'warn' } }
}
