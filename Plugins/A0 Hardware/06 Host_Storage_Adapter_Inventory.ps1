# Start of Settings
# End of Settings

$Title          = 'Host Storage Adapter Inventory'
$Header         = 'Per-host HBA inventory (model + firmware drift)'
$Comments       = 'HBA firmware drift across hosts in the same cluster causes path failover delays.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'P3'
$Recommendation = 'Standardize HBA firmware via vendor tooling (Dell DSU, HPE SUM, Lenovo XClarity).'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    foreach ($a in $h.ExtensionData.Config.StorageDevice.HostBusAdapter) {
        [pscustomobject]@{
            Host    = $h.Name
            Adapter = $a.Device
            Model   = $a.Model
            Driver  = $a.Driver
        }
    }
}
