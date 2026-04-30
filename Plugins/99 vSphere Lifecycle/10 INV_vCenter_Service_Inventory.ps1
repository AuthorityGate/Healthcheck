# Start of Settings
# End of Settings

$Title          = 'vCenter Service Inventory'
$Header         = 'vCenter local services + state'
$Comments       = 'Reference: vCenter VAMI -> Services. Critical services: vmware-vpostgres, vmware-vapi-endpoint, vmware-vmon, vsphere-ui, eam, vsan-health.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'Info'
$Recommendation = "Anything 'STOPPED' that should be running indicates a failed boot of vCenter; check VAMI immediately."

if (-not $Global:VCConnected) { return }
[pscustomobject]@{
    Note      = 'PowerCLI cannot enumerate VAMI services. Use https://<vc>:5480/#/appliance/services or service-control on the VCSA shell.'
    Reference = 'vCenter Server VAMI Services panel'
}
