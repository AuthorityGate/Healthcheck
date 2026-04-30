# Start of Settings
$LookbackHours = 168  # 7 days
# End of Settings

$Title          = "App Volumes Admin Audit Log"
$Header         = "[count] administrative action(s) in last $LookbackHours h"
$Comments       = "Who changed what in App Volumes Manager - assignments created/removed, packages imported, configuration toggled, AD configs edited. Change log is essential for audit + post-incident review."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "91 App Volumes"
$Severity       = "Info"
$Recommendation = "Unexpected entries (assignments removed by someone you don't recognize) usually mean compromised admin credentials. Stale admins should be removed."

if (-not (Get-AVRestSession)) { return }
$events = @()
try { $events = @(Get-AVAdminAuditLog) } catch { }
if (-not $events -or $events.Count -eq 0) {
    [pscustomobject]@{ Note = 'Admin-audit endpoint not exposed (older AppVol build).' }
    return
}
$cutoff = (Get-Date).AddHours(-$LookbackHours)
foreach ($e in $events) {
    $when = $null
    try { $when = [datetime]$e.created_at } catch { }
    if ($when -and $when -lt $cutoff) { continue }
    [pscustomobject]@{
        WhenUtc = if ($when) { $when.ToUniversalTime().ToString('yyyy-MM-dd HH:mm') } else { $e.created_at }
        Admin   = $e.admin_name
        Action  = $e.action
        Target  = $e.target_type
        Subject = $e.target_name
        Detail  = if ($e.detail) { ($e.detail.ToString()).Substring(0, [Math]::Min(180, $e.detail.ToString().Length)) } else { '' }
    }
}
