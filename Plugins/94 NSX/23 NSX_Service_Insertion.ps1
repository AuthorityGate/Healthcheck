# Start of Settings
# End of Settings

$Title          = 'NSX Service Insertion'
$Header         = '[count] service insertion definition(s) (IDS/IPS/AV)'
$Comments       = 'Service Insertion routes traffic through 3rd-party security VMs (Palo Alto, McAfee, Bitdefender).'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'Info'
$Recommendation = 'Confirm partner VM health if SI is deployed.'

if (-not (Get-NSXRestSession)) { return }
try { $si = Invoke-NSXRest -Path '/api/v1/serviceinsertion/services' } catch { return }
if (-not $si) { return }
foreach ($x in $si) {
    [pscustomobject]@{ Name=$x.display_name; Functionality=$x.functionalities -join ','; Partner=$x.attachment_point }
}
