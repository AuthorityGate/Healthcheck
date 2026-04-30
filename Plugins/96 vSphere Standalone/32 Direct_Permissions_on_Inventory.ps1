# Start of Settings
# End of Settings

$Title          = 'Direct Permissions on Inventory'
$Header         = '[count] permission grant(s) at object level (not propagated)'
$Comments       = 'Direct (non-propagated) grants bypass the role-RBAC model and are difficult to audit.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Convert to AD group + role at the closest container. Re-bind with Propagate=True.'

if (-not $Global:VCConnected) { return }
Get-VIPermission -ErrorAction SilentlyContinue | Where-Object { -not $_.Propagate } | ForEach-Object {
    [pscustomobject]@{ Entity=$_.Entity; Principal=$_.Principal; Role=$_.Role }
}
