# Start of Settings
# End of Settings

$Title          = 'Host Storage Adapter Inventory'
$Header         = 'Per-host HBA model + driver'
$Comments       = 'FC / iSCSI / SAS / SATA / NVMe storage adapters with vendor model + driver. Firmware drift and HCL violations show up here first.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'Info'
$Recommendation = 'Match HBA driver+firmware to vendor compatibility matrix; mismatch causes path-failover delays.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    foreach ($a in $h.ExtensionData.Config.StorageDevice.HostBusAdapter) {
        [pscustomobject]@{
            Host       = $h.Name
            Device     = $a.Device
            Model      = $a.Model
            Driver     = $a.Driver
            Bus        = $a.Bus
            Slot       = $a.Slot
            Status     = $a.Status
        }
    }
}
