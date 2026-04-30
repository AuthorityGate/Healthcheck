# Start of Settings
# End of Settings

$Title          = 'vSAN Witness Node Health'
$Header         = 'Witness reachable + version match'
$Comments       = 'Witness host must match vSAN version of the data hosts. Skew breaks 2-node / stretched cluster.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'P1'
$Recommendation = 'Re-deploy witness from current OVA. Verify TCP/2233 reachable.'

if (-not $Global:VCConnected) { return }
[pscustomobject]@{
    Note = 'Witness ping + version check is a manual cross-reference. Use Get-VsanWitnessTraffic + version match.'
    Reference = 'KB 2114803'
}
