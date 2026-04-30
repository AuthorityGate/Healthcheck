# Start of Settings
# End of Settings

$Title          = 'vSAN Disk Group Composition'
$Header         = '[count] disk group(s) across all vSAN clusters'
$Comments       = 'Disk groups are the failure unit (OSA). Each group: 1 cache + 1-7 capacity. ESA: flat NVMe pool.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'P3'
$Recommendation = 'Standardize disk group sizes across the cluster.'

if (-not $Global:VCConnected) { return }
Get-VsanDiskGroup -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        Cluster      = $_.Cluster.Name
        Host         = $_.VMHost.Name
        Type         = $_.DiskGroupType
        DiskCount    = $_.ExtensionData.Disk.Count
        TotalCapacityGB = [math]::Round((($_.ExtensionData.Disk | Measure-Object Capacity -Sum).Sum / 1GB), 1)
    }
}
