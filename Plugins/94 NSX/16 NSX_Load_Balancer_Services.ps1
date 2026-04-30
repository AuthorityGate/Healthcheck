# Start of Settings
# End of Settings

$Title          = 'NSX Load Balancer Services'
$Header         = '[count] LB service(s)'
$Comments       = 'Per-T1 LB services; verify VIPs reachable.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'Info'
$Recommendation = 'Periodically synthetic-test each VIP from outside.'

if (-not (Get-NSXRestSession)) { return }
$lb = Get-NSXLoadBalancer
if (-not $lb) { return }
foreach ($x in $lb) {
    [pscustomobject]@{
        Name      = $x.display_name
        Size      = $x.size
        Enabled   = $x.enabled
        T1Path    = $x.connectivity_path
    }
}
