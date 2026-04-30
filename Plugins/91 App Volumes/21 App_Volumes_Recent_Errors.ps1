# Start of Settings
# End of Settings

$Title          = 'App Volumes Recent Errors'
$Header         = 'Recent AV admin / system event errors'
$Comments       = 'Errors in AV log surface SQL deadlocks, vCenter timeout, and orphan cleanup failures.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P3'
$Recommendation = 'Pull from /cv_api/system_messages. Filter recent ERRORs and resolve.'

if (-not (Get-AVRestSession)) { return }
try { $msgs = Invoke-AVRest -Path '/cv_api/system_messages' } catch { return }
if (-not $msgs) { return }
foreach ($m in $msgs.system_messages) {
    if ($m.severity -in 'error','critical') {
        [pscustomobject]@{ Severity=$m.severity; Time=$m.created_at; Message=$m.message.Substring(0, [Math]::Min(120, $m.message.Length)) }
    }
}
