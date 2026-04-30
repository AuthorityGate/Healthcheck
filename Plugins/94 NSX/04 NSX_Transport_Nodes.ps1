# Start of Settings
# End of Settings

$Title          = 'NSX Transport Nodes'
$Header         = '[count] transport node(s)'
$Comments       = "Transport nodes (host TNs + edge TNs) are the data plane. Any 'DOWN' breaks DFW/segments."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P1'
$Recommendation = 'Re-prepare or re-deploy DOWN transport nodes. Verify N-VDS / VDS health.'

if (-not (Get-NSXRestSession)) { return }
$t = Get-NSXTransportNode
if (-not $t) { return }
foreach ($x in $t) {
    if ($x.node_deployment_info.deployment_type -ne $null -or $x.node_deployment_info.resource_type -ne $null) {
        [pscustomobject]@{
            Name      = $x.display_name
            Type      = $x.resource_type
            Version   = $x.node_deployment_info.deployment_version
            State     = $x.state
        }
    }
}
