# Start of Settings
# End of Settings

$Title          = 'NSX Edge Cluster'
$Header         = '[count] edge cluster(s)'
$Comments       = 'Edges run T0 / T1 service routers. Sized too small = throughput cap.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'Info'
$Recommendation = "Right-size edges per the NSX Sizing Guide. Plan 'large' or 'extra-large' for north-south VDI traffic."

if (-not (Get-NSXRestSession)) { return }
$e = Get-NSXEdgeCluster
if (-not $e) { return }
foreach ($c in $e) {
    [pscustomobject]@{
        Name           = $c.display_name
        MemberCount    = if ($c.members) { @($c.members).Count } else { 0 }
        FormFactor     = $c.deployment_type
    }
}
