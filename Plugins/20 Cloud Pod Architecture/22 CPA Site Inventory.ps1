# Start of Settings
# End of Settings

$Title          = 'CPA Sites'
$Header         = '[count] sites in the federation'
$Comments       = "Reference: 'Cloud Pod Architecture' Horizon docs. A site groups pods sharing low-latency interconnect; CPA users with 'home site' steer to the closest pod."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '20 Cloud Pod Architecture'
$Severity       = 'Info'
$Recommendation = 'Confirm site assignments match the physical / logical regions. Re-tag pods if datacenters move.'

if (-not (Get-HVRestSession)) { return }
$s = Get-HVSite
if (-not $s) { return }
foreach ($x in $s) {
    [pscustomobject]@{
        Name        = $x.name
        Description = $x.description
        PodCount    = if ($x.pods) { @($x.pods).Count } else { 0 }
    }
}

