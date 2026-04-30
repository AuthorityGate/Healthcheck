# Start of Settings
# End of Settings

$Title          = 'NSX User Inventory'
$Header         = '[count] NSX user(s) (local + LDAP)'
$Comments       = 'Local user inventory for break-glass; LDAP sync for normal admin.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'Info'
$Recommendation = "Verify local 'admin' password rotation. Audit AD bindings."

if (-not (Get-NSXRestSession)) { return }
try { $u = Invoke-NSXRest -Path '/api/v1/aaa/users' } catch { return }
if (-not $u) { return }
foreach ($x in $u) {
    [pscustomobject]@{ Username=$x.username; UserType=$x.user_type; Roles=($x.roles_for_paths | ForEach-Object { $_.roles[0].role }) -join ',' }
}
