# Start of Settings
$LookbackDays = 30
$MaxRowsRendered = 500
# End of Settings

$Title          = "Nutanix All Alerts (last $LookbackDays days)"
$Header         = "[count] alert(s) raised in the last $LookbackDays days (capped at $MaxRowsRendered rows)"
$Comments       = "Comprehensive 30-day alert log from Prism. Lists every alert (CRITICAL / WARNING / INFO) regardless of resolved state. The 24-hour Active Alerts plugin (08) catches what is happening NOW; this plugin shows the cumulative pattern. Recurring CRITICAL / WARNING categories - NCC check failures, disk SMART predictions, fan / temperature sensors - indicate hardware that is decaying and should be flagged for replacement before it fails."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "P2"
$Recommendation = "Group alerts by Title. Top recurring titles drive next-action: 'Disk SMART predictive failure' = schedule LCM disk replace; 'Curator scan slow' = check cluster I/O profile; 'CVM crash' = open Nutanix support case. Alerts auto-resolve when condition clears - resolved alerts are KEPT in this view because the historical pattern matters."

if (-not (Get-NTNXRestSession)) { return }
$alerts = @(Get-NTNXAlert)
if (-not $alerts) {
    [pscustomobject]@{ Note='No alerts returned (or view_alert permission missing on the audit account).' }
    return
}
$cutoff = [DateTimeOffset]::UtcNow.AddDays(-$LookbackDays).ToUnixTimeMilliseconds() * 1000

$matched = @()
foreach ($a in $alerts) {
    $when = if ($a.creation_time) { [long]$a.creation_time } else { 0 }
    if ($when -lt $cutoff) { continue }
    $matched += [pscustomobject]@{
        WhenUtc        = if ($when) { [datetimeoffset]::FromUnixTimeMilliseconds([long]$when / 1000).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') } else { '' }
        WhenRaw        = $when
        Severity       = "$($a.severity)"
        Cluster        = if ($a.cluster_reference) { "$($a.cluster_reference.name)" } else { '' }
        Title          = if ($a.alert_title) { "$($a.alert_title)" } else { "$($a.title)" }
        Resolved       = [bool]$a.resolved
        Acknowledged   = [bool]$a.acknowledged
        AlertType      = "$($a.alert_type_uuid)"
        AffectedEntity = if ($a.affected_entities) { ($a.affected_entities | ForEach-Object { $_.name } | Select-Object -First 3) -join '; ' } else { '' }
    }
}
$matched = @($matched | Sort-Object WhenRaw -Descending)
$total = $matched.Count
if ($total -eq 0) {
    [pscustomobject]@{ Note="No alerts in the last $LookbackDays days." }
    return
}
$matched | Select-Object -First $MaxRowsRendered | Select-Object WhenUtc,Severity,Cluster,Title,Resolved,Acknowledged,AlertType,AffectedEntity
if ($total -gt $MaxRowsRendered) {
    [pscustomobject]@{ WhenUtc=''; Severity='INFO'; Cluster=''; Title='TRUNCATED'; Resolved=''; Acknowledged=''; AlertType=''; AffectedEntity="$total total alerts; rendering first $MaxRowsRendered." }
}

$TableFormat = @{
    Severity     = { param($v,$row) if ("$v" -match 'CRITICAL') { 'bad' } elseif ("$v" -match 'WARNING') { 'warn' } elseif ("$v" -match 'INFO') { 'ok' } else { '' } }
    Resolved     = { param($v,$row) if ($v -eq $true) { 'ok' } elseif ($v -eq $false) { 'warn' } else { '' } }
    Acknowledged = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
}
