# Start of Settings
$LookbackHours = 24
# End of Settings

$Title          = "Nutanix Active Alerts (last $LookbackHours h)"
$Header         = "[count] alert(s) raised in the last $LookbackHours hours"
$Comments       = "All Prism alerts in the lookback window with severity, originating cluster, affected entity, and acknowledged state. Equivalent of vCenter's Recently Failed Tasks + Hardware Health Sensors. CRITICAL severity = immediate attention; WARNING = same-week."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "P1"
$Recommendation = "Acknowledge + resolve all CRITICAL alerts. Recurring WARNING alerts (e.g., 'Disk SMART fail predictions') indicate hardware decay - schedule LCM check. Use Prism Pulse (telemetry) for trend analysis if Pulse is enabled."

if (-not (Get-NTNXRestSession)) { return }
$alerts = @(Get-NTNXAlert)
if (-not $alerts) {
    [pscustomobject]@{ Note='No alerts returned (or view_alert permission missing).' }
    return
}
$cutoff = [DateTimeOffset]::UtcNow.AddHours(-$LookbackHours).ToUnixTimeMilliseconds() * 1000

$rendered = 0
foreach ($a in $alerts) {
    $when = if ($a.creation_time) { [long]$a.creation_time } else { 0 }
    if ($when -lt $cutoff) { continue }
    [pscustomobject]@{
        WhenUtc    = if ($when) { [datetimeoffset]::FromUnixTimeMilliseconds([long]$when / 1000).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') } else { '' }
        Severity   = $a.severity
        Cluster    = if ($a.cluster_reference) { $a.cluster_reference.name } else { '' }
        Title      = if ($a.alert_title) { $a.alert_title } else { $a.title }
        Resolved   = [bool]$a.resolved
        Acknowledged = [bool]$a.acknowledged
        AlertType  = $a.alert_type_uuid
        AffectedEntity = if ($a.affected_entities) { ($a.affected_entities | ForEach-Object { $_.name } | Select-Object -First 3) -join '; ' } else { '' }
    }
    $rendered++
}
if ($rendered -eq 0) {
    [pscustomobject]@{ Note="No alerts in the last $LookbackHours hours." }
}

$TableFormat = @{
    Severity = { param($v,$row) if ($v -match 'CRITICAL') { 'bad' } elseif ($v -match 'WARNING') { 'warn' } elseif ($v -match 'INFO') { 'ok' } else { '' } }
    Resolved = { param($v,$row) if ($v -eq $true) { 'ok' } else { 'warn' } }
}
