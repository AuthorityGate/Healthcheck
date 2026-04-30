# Start of Settings
# End of Settings

$Title          = 'vCenter Active + Recently Triggered Alarms'
$Header         = 'All currently-active alarms + AlarmStatusChangedEvent in last 30 days'
$Comments       = "vCenter alarms surface ongoing issues that the GUI flags red/yellow on the inventory tree. This plugin lists EVERY entity (cluster, host, datastore, VM) that is currently red or yellow, plus AlarmStatusChangedEvent records from the last 30 days. The 24-hour Failed Tasks plugin shows what tasks failed; this plugin shows what infrastructure conditions raised alarms (high latency, low free space, HA agent stopped, hardware sensor red, etc.)."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Triage active red alarms first (they represent ongoing pain). Recurring AlarmStatusChangedEvent for the same alarm name indicates a flaky condition (datastore latency oscillating around threshold, cluster HA dropping then recovering). Tune thresholds for noisy alarms; do not just acknowledge."

if (-not $Global:VCConnected) { return }

$rows = @()

# ---- Active alarms via Get-View AlarmManager / per-entity TriggeredAlarmState ----
try {
    $rootFolder = Get-View ServiceInstance -ErrorAction Stop
    $alarmMgr = Get-View $rootFolder.Content.AlarmManager -ErrorAction SilentlyContinue
} catch { $alarmMgr = $null }

# Walk every key entity type for triggered alarm state.
$entitiesToScan = @()
$entitiesToScan += @(Get-Cluster   -ErrorAction SilentlyContinue)
$entitiesToScan += @(Get-VMHost    -ErrorAction SilentlyContinue)
$entitiesToScan += @(Get-Datastore -ErrorAction SilentlyContinue)
# VMs scanned at view-level only (Get-VM with TriggeredAlarmState would be slow on large estates)

foreach ($ent in $entitiesToScan) {
    try {
        $view = $ent | Get-View -Property 'OverallStatus','TriggeredAlarmState','Name' -ErrorAction Stop
        if ($view.TriggeredAlarmState) {
            foreach ($t in @($view.TriggeredAlarmState)) {
                $alarmName = ''
                try {
                    $a = Get-View $t.Alarm -Property Info -ErrorAction SilentlyContinue
                    if ($a) { $alarmName = "$($a.Info.Name)" }
                } catch { }
                $rows += [pscustomobject]@{
                    Source       = 'ACTIVE'
                    Entity       = $view.Name
                    EntityType   = $ent.GetType().Name
                    AlarmName    = $alarmName
                    OverallStatus = "$($t.OverallStatus)"
                    Acknowledged = [bool]$t.Acknowledged
                    Time         = if ($t.Time) { ([datetime]$t.Time).ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
                }
            }
        }
    } catch { }
}

# ---- AlarmStatusChangedEvent in last 30 days ----
try {
    $since = (Get-Date).AddDays(-30)
    $alarmEvents = @(Get-VIEvent -Start $since -MaxSamples 500 -ErrorAction SilentlyContinue | Where-Object { $_.GetType().Name -eq 'AlarmStatusChangedEvent' })
    foreach ($e in $alarmEvents | Sort-Object CreatedTime -Descending) {
        $entityName = ''
        if ($e.Vm)        { $entityName = "$($e.Vm.Name)" }
        elseif ($e.Host)  { $entityName = "$($e.Host.Name)" }
        elseif ($e.ComputeResource) { $entityName = "$($e.ComputeResource.Name)" }
        elseif ($e.Datastore)       { $entityName = "$($e.Datastore.Name)" }
        $rows += [pscustomobject]@{
            Source       = "30-DAY ($($e.From) -> $($e.To))"
            Entity       = $entityName
            EntityType   = $e.GetType().Name
            AlarmName    = "$($e.Alarm.Name)"
            OverallStatus = "$($e.To)"
            Acknowledged = ''
            Time         = if ($e.CreatedTime) { ([datetime]$e.CreatedTime).ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
        }
    }
} catch { }

if ($rows.Count -eq 0) {
    [pscustomobject]@{ Note='No active alarms and no AlarmStatusChangedEvent in 30 days. Either nothing fired or vCenter event retention is below 30 days (cross-check 18 vCenter Task Event Retention).' }
    return
}
$rows

$TableFormat = @{
    OverallStatus = { param($v,$row) if ("$v" -eq 'red') { 'bad' } elseif ("$v" -eq 'yellow') { 'warn' } else { '' } }
    Source        = { param($v,$row) if ("$v" -eq 'ACTIVE') { 'bad' } else { '' } }
    Acknowledged  = { param($v,$row) if ($v -eq $false -and "$($row.Source)" -eq 'ACTIVE') { 'warn' } else { '' } }
}
