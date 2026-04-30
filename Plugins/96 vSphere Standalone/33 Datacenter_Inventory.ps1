# Start of Settings
# End of Settings

$Title          = 'Datacenter Inventory'
$Header         = 'vCenter datacenter inventory + entity counts'
$Comments       = 'Top-level posture summary; baseline for capacity discussions.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'Info'
$Recommendation = 'Maintain one datacenter per physical location for clarity.'

if (-not $Global:VCConnected) { return }
Get-Datacenter -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        Datacenter = $_.Name
        Clusters   = @(Get-Cluster -Location $_).Count
        Hosts      = @(Get-VMHost -Location $_).Count
        VMs        = @(Get-VM -Location $_).Count
        Datastores = @(Get-Datastore -Location $_).Count
    }
}
