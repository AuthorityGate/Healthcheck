# Start of Settings
# End of Settings

$Title          = 'NSX Manager Nodes'
$Header         = '[count] manager node(s)'
$Comments       = 'Verify the cluster has 3 manager nodes (production) and they share the same version.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P1'
$Recommendation = "Replace failed nodes via 'Add NSX Manager' wizard. Confirm same build across the trio."

if (-not (Get-NSXRestSession)) { return }
$n = Get-NSXClusterNode
if (-not $n) { return }
foreach ($x in $n) {
    [pscustomobject]@{
        Hostname   = $x.fqdn
        Version    = $x.version
        Roles      = ($x.controller_role -join ', ')
        Status     = $x.status
    }
}
