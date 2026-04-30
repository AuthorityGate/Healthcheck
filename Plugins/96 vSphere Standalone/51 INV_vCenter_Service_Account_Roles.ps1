# Start of Settings
# End of Settings

$Title          = 'vCenter Service Account Roles'
$Header         = 'Effective role(s) of the connecting user'
$Comments       = 'Which vCenter roles are bound to the user this scan ran as. Shows over-privileged or under-privileged access patterns.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'Info'
$Recommendation = 'Read-only at the root is sufficient for inventory; some checks want System.Read.'

if (-not $Global:VCConnected) { return }
$vc = $global:DefaultVIServer
if (-not $vc) { return }
Get-VIPermission -ErrorAction SilentlyContinue | Where-Object { $_.Principal -eq $vc.User } | ForEach-Object {
    [pscustomobject]@{
        Principal = $_.Principal
        Role      = $_.Role
        Entity    = $_.Entity
        Propagate = $_.Propagate
    }
}
