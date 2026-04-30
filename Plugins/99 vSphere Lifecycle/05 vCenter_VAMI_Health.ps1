# Start of Settings
# End of Settings

$Title          = 'vCenter VAMI Health'
$Header         = 'VCSA service health snapshot'
$Comments       = "VAMI exposes per-service status: vmware-vpostgres, vmware-vapi-endpoint, etc. Anything 'down' is a degradation."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P1'
$Recommendation = 'Restart the affected service via VAMI -> Services. Investigate disk space if vmware-postgres is down.'

if (-not $Global:VCConnected) { return }
[pscustomobject]@{
    Note = 'VAMI port 5480 + a separate VAPI session token are required. Beyond PowerCLI core.'
    Reference = 'https://<vc>:5480/#/appliance/services'
}
