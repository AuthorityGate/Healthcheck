# Start of Settings
# 30 days = 720 hours. Some Horizon Event DB defaults retain only 7 days;
# if your retention is shorter the API returns whatever it has.
$LookbackDays = 30
$MaxRowsRendered = 500
# End of Settings

$Title          = 'Horizon Critical / Error Events (last 30 days)'
$Header         = "[count] Horizon ERROR / AUDIT_FAIL / WARNING event(s) in the last $LookbackDays days (capped at $MaxRowsRendered rows)"
$Comments       = "Comprehensive 30-day error log from the Horizon Event Database (audit_events). Pulls AUDIT_FAIL, ERROR, and WARNING severities. Use this as the input to the customer's incident-trend conversation: the same event repeated 1,000 times in 30 days is a known broken thing the help desk has been masking. Empty result = either Event DB retention is set below 30 days OR this is a healthy environment (cross-check Event Database Status plugin)."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '70 Events'
$Severity       = 'P2'
$Recommendation = "Group findings by EventType + Source. The top 5 EventType counts almost always reveal the operational pain points (auth failures, machine provisioning failures, push-image failures, cert validation failures). Forward these to SIEM via Event Database syslog so the data survives DB rotation."

try {
    $events = Get-HVAuditEvent -SinceHours ($LookbackDays * 24)
} catch {
    [pscustomobject]@{ Note="Audit event lookup failed: $($_.Exception.Message). The Event Database may be offline (cross-check 14 Event Database Status) or the audit account lacks the Administrators (Read-only) role."; }
    return
}
if (-not $events) {
    [pscustomobject]@{ Note="No ERROR / AUDIT_FAIL / WARNING events returned for $LookbackDays days. Verify Event Database retention is at least $LookbackDays days; default is shorter."; }
    return
}

$rows = @($events | Sort-Object @{e='time';asc=$false} | Select-Object -First $MaxRowsRendered)
$totalCount = @($events).Count
foreach ($e in $rows) {
    $when = if ($e.time) { (Get-Date '1970-01-01').AddMilliseconds([long]$e.time).ToLocalTime() } else { $null }
    [pscustomobject]@{
        Time      = if ($when) { $when.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
        Severity  = "$($e.severity)"
        Module    = "$($e.module)"
        Source    = "$($e.source)"
        EventType = "$($e.event_type)"
        User      = if ($e.user_name) { "$($e.user_name)" } elseif ($e.user_id) { "$($e.user_id)" } else { '' }
        Machine   = if ($e.machine_name) { "$($e.machine_name)" } elseif ($e.machine_id) { "$($e.machine_id)" } else { '' }
        Message   = if ($e.message) { "$($e.message)".Substring(0, [Math]::Min(180, "$($e.message)".Length)) } else { '' }
    }
}
if ($totalCount -gt $MaxRowsRendered) {
    [pscustomobject]@{ Time=''; Severity='INFO'; Module=''; Source=''; EventType='TRUNCATED'; User=''; Machine=''; Message="$totalCount total events; rendering first $MaxRowsRendered. Adjust MaxRowsRendered in plugin settings to expand."; }
}

$TableFormat = @{
    Severity = { param($v,$row) if ("$v" -eq 'AUDIT_FAIL' -or "$v" -eq 'ERROR') { 'bad' } elseif ("$v" -eq 'WARNING') { 'warn' } else { '' } }
}
