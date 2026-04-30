# Start of Settings
# End of Settings

$Title          = 'vSAN Disk Inventory'
$Header         = 'Per-disk inventory across vSAN clusters'
$Comments       = 'Every vSAN-claimed disk: host, naa-id, model, vendor, capacity, role (cache vs capacity), disk-group membership.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'Info'
$Recommendation = 'Track disk-firmware drift via the model column - mismatched firmware on disks of the same model is HCL-violation territory.'

if (-not $Global:VCConnected) { return }
Get-VsanDiskGroup -ErrorAction SilentlyContinue | ForEach-Object {
    $dg = $_
    foreach ($d in $dg.ExtensionData.Disk) {
        [pscustomobject]@{
            Cluster    = $dg.Cluster.Name
            Host       = $dg.VMHost.Name
            DiskGroup  = $dg.Name
            DiskGroupType = $dg.DiskGroupType
            DeviceName = $d.CanonicalName
            Vendor     = $d.Vendor
            Model      = $d.Model
            Role       = if ($d.Ssd -and ($d.CanonicalName -in $dg.ExtensionData.Ssd.CanonicalName)) { 'cache' } else { if ($d.Ssd) { 'capacity-ssd' } else { 'capacity-hdd' } }
            CapacityGB = [math]::Round($d.Capacity / 1GB, 1)
        }
    }
}
