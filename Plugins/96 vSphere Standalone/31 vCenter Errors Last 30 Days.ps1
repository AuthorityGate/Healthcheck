# Start of Settings
# Look-back window in days. vCenter retains tasks/events per the
# 'event/task retention' advanced setting (default: 30 days).
$LookbackDays = 30
$MaxRowsRendered = 500
# End of Settings

$Title          = 'vCenter Errors + Failed Tasks (last 30 days)'
$Header         = "[count] vCenter Error event(s) in the last $LookbackDays days (capped at $MaxRowsRendered rows)"
$Comments       = "Comprehensive 30-day error log from vCenter via Get-VIEvent. Pulls Error-level events: failed tasks (clone, migrate, power-on, snapshot), HA failovers, host-disconnect events, alarm-triggered events, datastore alerts. The 24-hour 'Recently Failed Tasks' plugin (30) catches today's noise; this plugin surfaces month-over-month patterns. Empty result = either vCenter event/task retention is set below 30 days OR the environment is genuinely quiet."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P2'
$Recommendation = "Group findings by Type. Repeating event types reveal infrastructure trends: TaskEvent failures cluster around storage; HostConnectionLostEvent indicates network drift; VmDasResetEvent indicates HA-triggered restarts. Forward vCenter events to SIEM via syslog (vCenter Server -> Administration -> System Configuration -> Services -> Syslog). Verify event retention >= 90 days for compliance evidence (cross-check 18 vCenter Task Event Retention)."

if (-not $Global:VCConnected) { return }
$start = (Get-Date).AddDays(-$LookbackDays)
try {
    $events = @(Get-VIEvent -Start $start -Types Error -MaxSamples ($MaxRowsRendered + 1) -ErrorAction Stop)
} catch {
    [pscustomobject]@{ Note="Get-VIEvent failed: $($_.Exception.Message). Verify vCenter connection and audit account permissions on event log." }
    return
}
if ($events.Count -eq 0) {
    [pscustomobject]@{ Note="No Error events returned for the last $LookbackDays days. Verify event retention setting (Administration -> System Configuration -> Database) is at least $LookbackDays days." }
    return
}
$rows = @($events | Sort-Object CreatedTime -Descending | Select-Object -First $MaxRowsRendered)
foreach ($ev in $rows) {
    $msg = "$($ev.FullFormattedMessage)" -replace "`r|`n", ' '
    $entityName = ''
    if ($ev.Vm)         { $entityName = "$($ev.Vm.Name)" }
    elseif ($ev.Host)   { $entityName = "$($ev.Host.Name)" }
    elseif ($ev.ComputeResource) { $entityName = "$($ev.ComputeResource.Name)" }
    elseif ($ev.Datacenter)      { $entityName = "$($ev.Datacenter.Name)" }
    elseif ($ev.Datastore)       { $entityName = "$($ev.Datastore.Name)" }

    [pscustomobject]@{
        Time     = if ($ev.CreatedTime) { ([datetime]$ev.CreatedTime).ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
        Type     = $ev.GetType().Name
        Entity   = $entityName
        User     = "$($ev.UserName)"
        Message  = if ($msg) { $msg.Substring(0, [Math]::Min(220, $msg.Length)) } else { '' }
    }
}
if ($events.Count -gt $MaxRowsRendered) {
    [pscustomobject]@{ Time=''; Type='TRUNCATED'; Entity=''; User=''; Message="$($events.Count) total Error events; rendering first $MaxRowsRendered. Increase MaxRowsRendered in plugin settings if you need the full set." }
}

$TableFormat = @{
    Type = { param($v,$row) if ("$v" -match 'TaskEvent|HostConnectionLost|HostDasError|VmDasError|HostNotResponding') { 'bad' } else { '' } }
}
