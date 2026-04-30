# Start of Settings
# End of Settings

$Title          = "Active vCenter Alarms (Red / Yellow)"
$Header         = "[count] active vCenter alarm(s)"
$Comments       = "Triaged list of fired alarms across the inventory. Common Horizon-affecting alarms: 'Datastore usage on disk', 'Host connection and power state', 'License inventory monitoring', 'Storage path redundancy lost', 'VM CPU ready time'."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P2"
$Recommendation = "Acknowledge or remediate each alarm. Suppressing without remediation is documented but discouraged - it hides Horizon storage / license / capacity issues that surface as user-facing connection failures."

if (-not $Global:VCConnected) { return }

$rootFolder = Get-Folder -NoRecursion | Where-Object { $_.Name -eq 'Datacenters' } | Select-Object -First 1
if (-not $rootFolder) { return }

# Walk all entities and collect TriggeredAlarmState
$entities = @()
$entities += Get-Datacenter -ErrorAction SilentlyContinue
$entities += Get-Cluster    -ErrorAction SilentlyContinue
$entities += Get-VMHost     -ErrorAction SilentlyContinue
$entities += Get-Datastore  -ErrorAction SilentlyContinue
$entities += Get-VM         -ErrorAction SilentlyContinue

$am = (Get-View -Id ($global:DefaultVIServer.ExtensionData.Content.AlarmManager))
$out = New-Object System.Collections.ArrayList
foreach ($e in $entities) {
    $ts = $e.ExtensionData.TriggeredAlarmState
    if (-not $ts) { continue }
    foreach ($t in $ts) {
        $alarm = $am.GetAlarm($t.Alarm)
        $entityType = ($e.GetType().Name -replace 'Impl$','')
        $null = $out.Add([pscustomobject]@{
            Entity   = $e.Name
            Type     = $entityType
            Alarm    = $alarm.Info.Name
            Severity = $t.OverallStatus
            Time     = $t.Time
            Ack      = $t.Acknowledged
        })
    }
}
$out | Sort-Object Severity, Entity

$TableFormat = @{
    Severity = { param($v,$row) if ($v -eq 'red') { 'bad' } elseif ($v -eq 'yellow') { 'warn' } else { '' } }
}
