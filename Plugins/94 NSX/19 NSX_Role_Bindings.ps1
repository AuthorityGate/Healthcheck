# Start of Settings
# End of Settings

$Title          = 'NSX Role Bindings'
$Header         = '[count] NSX role binding(s)'
$Comments       = 'AD-group based role bindings prevent break-glass lockout.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P2'
$Recommendation = 'Bind admin role to an AD group, not direct user.'

if (-not (Get-NSXRestSession)) { return }
try { $r = Invoke-NSXRest -Path '/api/v1/aaa/role-bindings' } catch { return }
if (-not $r) { return }
foreach ($x in $r) {
    [pscustomobject]@{ Name=$x.name; Type=$x.type; IdentitySource=$x.identity_source_type; Roles=($x.roles_for_paths.roles | ForEach-Object { $_.role }) -join ',' }
}
