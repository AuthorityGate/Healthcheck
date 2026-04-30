# Start of Settings
# End of Settings

$Title          = "App Volumes Activity Log (recent errors)"
$Header         = "[count] error / warning event(s) in App Volumes activity log"
$Comments       = "Pulls /cv_api/activity_logs/recent and surfaces non-success events: failed attaches, failed assignments, sync errors, capture failures. This is the canonical source for 'why didn't user X get app Y today'."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "91 App Volumes"
$Severity       = "P3"
$Recommendation = "Recurring attach failures usually mean storage permissions / VMDK lock issues. Capture failures point at provisioning-machine misconfiguration (KB 2148198). Sync errors point at AD reachability."

if (-not (Get-AVRestSession)) { return }
$events = @()
try { $events = @(Get-AVActivityRecent) } catch { }
if (-not $events -or $events.Count -eq 0) {
    [pscustomobject]@{ Note = 'No recent activity-log entries (or endpoint not exposed).' }
    return
}
$bad = $events | Where-Object { $_.status -match 'failed|error' -or $_.severity -match 'error|warning' } | Select-Object -First 200
if (-not $bad) {
    [pscustomobject]@{ Note = 'No errors/warnings in recent activity log.' }
    return
}
foreach ($e in $bad) {
    [pscustomobject]@{
        TimeUtc  = $e.created_at
        Status   = $e.status
        Severity = $e.severity
        Action   = $e.action
        Subject  = $e.subject
        Message  = if ($e.message) { ($e.message.ToString()).Substring(0, [Math]::Min(180, $e.message.ToString().Length)) } else { '' }
    }
}
