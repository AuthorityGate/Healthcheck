# Start of Settings
# End of Settings

$Title          = 'NSX Open Alarms'
$Header         = '[count] open NSX alarm(s)'
$Comments       = 'Open alarms (CPU, memory, manager partition, edge fail) flag service degradation.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P2'
$Recommendation = 'Triage by severity. CRITICAL alarms must be fixed before any change.'

if (-not (Get-NSXRestSession)) { return }
try { $a = Get-NSXAlarm } catch { return }
if (-not $a) { return }
foreach ($x in $a) {
    [pscustomobject]@{
        EventType = $x.event_type
        Severity  = $x.severity
        State     = $x.status
        Time      = $x.last_reported_time
        Node      = $x.node_display_name
    }
}
