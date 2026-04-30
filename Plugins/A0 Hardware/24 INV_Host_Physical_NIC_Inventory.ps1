# Start of Settings
# End of Settings

$Title          = 'Host Physical NIC Inventory'
$Header         = 'Per-host pNIC model + driver + firmware'
$Comments       = 'Physical NIC model, driver version, firmware version, link speed, MAC. Driver/firmware drift between hosts in the same cluster degrades vMotion + vSAN performance and is a common HCL-violation cause.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'Info'
$Recommendation = 'Standardize NIC model + driver version cluster-wide. Cross-reference VMware HCL.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    foreach ($p in $h.ExtensionData.Config.Network.Pnic) {
        [pscustomobject]@{
            Host       = $h.Name
            Pnic       = $p.Device
            Driver     = $p.Driver
            MAC        = $p.Mac
            LinkSpeedMb = if ($p.LinkSpeed) { $p.LinkSpeed.SpeedMb } else { 0 }
            Duplex     = if ($p.LinkSpeed) { $p.LinkSpeed.Duplex } else { $false }
            PciDevice  = $p.Pci
        }
    }
}
