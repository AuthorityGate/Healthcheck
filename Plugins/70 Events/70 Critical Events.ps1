# Start of Settings
# Look-back window in hours.
$EventLookbackHours = 24
# End of Settings

$Title          = "Critical / Audit-Fail Events"
$Header         = "[count] critical event(s) in the last $EventLookbackHours hours"
$Comments       = "Pulled from the Horizon event database (audit_events). Severities: AUDIT_FAIL, ERROR, WARNING."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "70 Events"
$Severity       = "P2"
$Recommendation = "Triage by event_type. Repeated AUDIT_FAIL_USER_NOT_AUTHORIZED or BROKER_USER_AUTHFAILED almost always indicates an AD or smart-card problem."

try {
    $events = Get-HVAuditEvent -SinceHours $EventLookbackHours
} catch {
    Write-Warning "Audit event lookup failed: $($_.Exception.Message)"
    return
}
if (-not $events) { return }

$events | ForEach-Object {
    [pscustomobject]@{
        Time     = if ($_.time) { (Get-Date '1970-01-01').AddMilliseconds($_.time).ToLocalTime() } else { $null }
        Severity = $_.severity
        Module   = $_.module
        Source   = $_.source
        EventType = $_.event_type
        User     = $_.user_id
        Machine  = $_.machine_id
        Message  = $_.message
    }
} | Sort-Object Time -Descending | Select-Object -First 200
