# Start of Settings
# End of Settings

$Title          = 'vSAN Network Latency'
$Header         = 'vSAN inter-node latency snapshot'
$Comments       = "Reference: 'vSAN Network Health'. Sustained > 1 ms = inadequate fabric."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'P2'
$Recommendation = 'Investigate switch QoS / oversubscription. vSAN benefits from dedicated NIC + jumbo frames.'

if (-not $Global:VCConnected) { return }
[pscustomobject]@{
    Note = 'vSAN network latency surfaces in Skyline Health -> Network -> "vSAN cluster partition / vSAN host network latency".'
    Reference = 'Skyline Health'
}
