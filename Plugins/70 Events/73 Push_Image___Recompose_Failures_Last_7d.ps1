# Start of Settings
# End of Settings

$Title          = 'Push Image / Recompose Failures Last 7d'
$Header         = '[count] image-push / recompose failure(s)'
$Comments       = "Image-push failures (instant clone) leave pools at the old image while reporting 'partial success'."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '70 Events'
$Severity       = 'P1'
$Recommendation = 'Resume push from Console or pull a fresh snapshot.'

try { $e = Get-HVAuditEvent -SinceHours 168 -Severities @('AUDIT_FAIL','ERROR','WARNING') } catch { return }
if (-not $e) { return }
$e | Where-Object { $_.event_type -match 'PUSH_IMAGE|RECOMPOSE' } | Select-Object -First 30 | ForEach-Object {
    [pscustomobject]@{
        Time     = if ($_.time) { (Get-Date '1970-01-01').AddMilliseconds($_.time).ToLocalTime() } else { $null }
        Event    = $_.event_type
        Pool     = $_.desktop_id
        Severity = $_.severity
    }
}
