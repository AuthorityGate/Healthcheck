# Start of Settings
# End of Settings

$Title          = 'Provisioning Failures Last 24h'
$Header         = '[count] provisioning failure event(s)'
$Comments       = 'Provisioning failures correlate with vCenter throttling, datastore full, customization error.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '70 Events'
$Severity       = 'P1'
$Recommendation = 'Triage by event_type (PROVISIONING_FAILURE, BROKER_PROVISIONING_ERROR). Verify vCenter health.'

try { $e = Get-HVAuditEvent -SinceHours 24 -Severities @('AUDIT_FAIL','ERROR') } catch { return }
if (-not $e) { return }
$e | Where-Object { $_.event_type -match 'PROVISION' } | Select-Object -First 50 | ForEach-Object {
    [pscustomobject]@{
        Time      = if ($_.time) { (Get-Date '1970-01-01').AddMilliseconds($_.time).ToLocalTime() } else { $null }
        Event     = $_.event_type
        Pool      = $_.desktop_id
        Machine   = $_.machine_id
        Severity  = $_.severity
        Message   = ($_.message -replace "`r|`n",' ').Substring(0, [Math]::Min(140, $_.message.Length))
    }
}
