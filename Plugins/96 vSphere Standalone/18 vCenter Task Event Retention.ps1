# Start of Settings
# Minimum acceptable retention (days) for vCenter Tasks + Events.
$MinTaskRetention  = 90
$MinEventRetention = 90
# End of Settings

$Title          = "vCenter Task / Event Retention"
$Header         = "Task + Event retention (days) compared to minimums"
$Comments       = "Reference: vCenter Server Admin Guide -> 'Database Configuration'. Default is 30 days (tasks) / 30 days (events). For audit and incident-response, 90+ days is recommended."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P3"
$Recommendation = "vCenter -> Configure -> Settings -> General -> Database. Set 'Tasks retention' and 'Events retention' to 90+ days. Confirm vPostgres has free space (vCenter VAMI -> Database)."

if (-not $Global:VCConnected) { return }
$vc = $global:DefaultVIServer
if (-not $vc) { return }

$si  = Get-View ServiceInstance
$opt = Get-View $si.Content.Setting
$map = @{}
foreach ($s in $opt.Setting) { $map[$s.Key] = $s.Value }

$taskDays  = [int]($map['task.maxAgeEnabled']  -replace '[^0-9]','')
$eventDays = [int]($map['event.maxAgeEnabled'] -replace '[^0-9]','')
# The actual day counts:
$taskAge   = [int]$map['task.maxAge']
$eventAge  = [int]$map['event.maxAge']

[pscustomobject]@{
    TaskMaxAgeEnabled  = [bool]$map['task.maxAgeEnabled']
    TaskMaxAgeDays     = $taskAge
    TaskMin            = $MinTaskRetention
    EventMaxAgeEnabled = [bool]$map['event.maxAgeEnabled']
    EventMaxAgeDays    = $eventAge
    EventMin           = $MinEventRetention
}

$TableFormat = @{
    TaskMaxAgeDays  = { param($v,$row) if ([int]$v -lt $row.TaskMin)  { 'warn' } else { 'ok' } }
    EventMaxAgeDays = { param($v,$row) if ([int]$v -lt $row.EventMin) { 'warn' } else { 'ok' } }
}
