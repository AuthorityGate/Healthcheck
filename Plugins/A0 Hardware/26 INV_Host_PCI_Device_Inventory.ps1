# Start of Settings
# End of Settings

$Title          = 'Host PCI Device Inventory'
$Header         = 'Per-host PCI device list (filtered to NIC / HBA / GPU)'
$Comments       = 'PCIe device tree showing NICs, HBAs, GPUs (for vGPU deployments). Useful for verifying GPU presence and PCIe slot mapping after hardware changes.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'Info'
$Recommendation = 'Snapshot annually or after any hardware swap.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    foreach ($d in $h.ExtensionData.Hardware.PciDevice) {
        $cc = $d.ClassId
        # filter: 0x02 = network, 0x01 = storage, 0x03 = display
        if (($cc -shr 8) -in 0x02, 0x01, 0x03) {
            [pscustomobject]@{
                Host       = $h.Name
                Vendor     = $d.VendorName
                Device     = $d.DeviceName
                ClassCode  = ('0x{0:X4}' -f $cc)
                ClassType  = switch (($cc -shr 8)) { 0x02 {'Network'}; 0x01 {'Storage'}; 0x03 {'Display/GPU'}; default {'Other'} }
                PciId      = $d.Id
            }
        }
    }
}
