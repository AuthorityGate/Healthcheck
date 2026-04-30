# Start of Settings
# End of Settings

$Title          = 'vCenter Active Tasks + Alarms'
$Header         = "[count] active task(s) and triggered alarm(s)"
$Comments       = "Long-running tasks (vMotion, clone, snapshot) and triggered alarms (red/yellow). Stuck tasks > 1h old = investigate. Triggered alarms unacknowledged > 24h = ops debt."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Cancel + investigate stuck tasks. Acknowledge or clear alarms. Reduce alarm noise via tuning thresholds + notification rules."

if (-not $Global:VCConnected) { return }

# Active tasks
foreach ($t in (Get-Task -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Running' -or $_.State -eq 'Queued' })) {
    $age = if ($t.StartTime) { [int]((Get-Date) - $t.StartTime).TotalMinutes } else { -1 }
    if ($age -ge 30) {
        $objName = ''
        if ($t.ObjectId) {
            try {
                $objView = Get-View $t.ObjectId -Property Name -ErrorAction Stop
                if ($objView) { $objName = $objView.Name }
            } catch { }
        }
        [pscustomobject]@{
            Type        = 'Task'
            Name        = $t.Name
            Object      = $objName
            State       = $t.State
            AgeMinutes  = $age
            PercentDone = if ($t.PercentComplete) { "$($t.PercentComplete)%" } else { '' }
            Note        = if ($age -gt 60) { 'Long-running task' } else { '' }
        }
    }
}

# Triggered alarms - iterate every entity type that can carry an alarm.
# PowerCLI's Get-View -ViewType does not accept the abstract 'ManagedEntity'
# union; enumerate the concrete subtypes instead.
$alarmEntityTypes = @('Datacenter','ClusterComputeResource','ComputeResource','HostSystem','VirtualMachine','Datastore','StoragePod','ResourcePool','Folder')
foreach ($vt in $alarmEntityTypes) {
    foreach ($e in (Get-View -ViewType $vt -Property Name,TriggeredAlarmState -ErrorAction SilentlyContinue)) {
        if (-not $e.TriggeredAlarmState) { continue }
        foreach ($alarm in @($e.TriggeredAlarmState)) {
            if ($alarm.Acknowledged) { continue }
            $alDef = $null
            if ($alarm.Alarm) {
                try { $alDef = Get-View $alarm.Alarm -Property Info -ErrorAction Stop } catch { }
            }
            $age = if ($alarm.Time) { [int]((Get-Date) - $alarm.Time).TotalHours } else { -1 }
            [pscustomobject]@{
                Type        = 'Alarm'
                Name        = if ($alDef) { $alDef.Info.Name } else { 'Unknown alarm' }
                Object      = $e.Name
                State       = $alarm.OverallStatus
                AgeMinutes  = if ($age -ge 0) { $age * 60 } else { '' }
                PercentDone = ''
                Note        = if ($age -ge 24) { 'Unacknowledged > 24h' } else { '' }
            }
        }
    }
}

$TableFormat = @{
    State = { param($v,$row) if ($v -eq 'red') { 'bad' } elseif ($v -eq 'yellow') { 'warn' } else { '' } }
    Note  = { param($v,$row) if ($v -match 'Long-running|> 24h') { 'warn' } else { '' } }
}
