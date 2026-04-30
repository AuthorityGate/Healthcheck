# Start of Settings
# End of Settings

$Title          = 'App Volumes Online Sessions'
$Header         = '[count] currently-attached AV volumes'
$Comments       = "Reference: 'Online Entities' (AV docs). Volumes attached to live sessions."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'Info'
$Recommendation = 'Sustained > 80% of license cap == buy more capacity.'

if (-not (Get-AVRestSession)) { return }
$o = Get-AVOnlineEntity
if (-not $o) { return }
[pscustomobject]@{
    OnlineCount = if ($o.online_entities) { @($o.online_entities).Count } else { 0 }
}
