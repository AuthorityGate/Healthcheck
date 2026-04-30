# Start of Settings
# End of Settings

$Title          = 'App Volumes Admin Roles'
$Header         = '[count] admin role / group assignment(s)'
$Comments       = "Reference: 'Admin Roles' (AV docs). Restrict who can create / assign packages. Default 'admin' should not be a user list."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P2'
$Recommendation = "Use AD groups for admin role assignment. Disable the local 'admin' user for production."

if (-not (Get-AVRestSession)) { return }
$r = Get-AVAdminGroup
if (-not $r) { return }
foreach ($x in $r.admin_groups) {
    [pscustomobject]@{
        Group = $x.name; Role = $x.role; UPN = $x.upn
    }
}
