# Start of Settings
# End of Settings

$Title          = 'vSAN Resync Activity'
$Header         = '[count] vSAN cluster(s) with active resync'
$Comments       = 'Active resync indicates recent host/disk loss or policy change. Sustained resync stresses the network.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'P3'
$Recommendation = "Check 'Cluster -> Monitor -> vSAN -> Resyncing components'. If chronic, capacity is too tight."

if (-not $Global:VCConnected) { return }
Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.VsanEnabled } | ForEach-Object {
    $vsan = $_ | Get-VsanSpaceUsage -ErrorAction SilentlyContinue
    if (-not $vsan) { return }
    # vSAN cluster with no claimed disks reports TotalCapacityGB=0; skip the
    # divide-by-zero rather than emitting a meaningless row.
    if (-not $vsan.TotalCapacityGB -or $vsan.TotalCapacityGB -le 0) {
        [pscustomobject]@{
            Cluster         = $_.Name
            TotalCapacityGB = 0
            FreeCapacityGB  = 0
            UsedPercent     = 0
            Note            = 'vSAN enabled but no disks claimed - cluster likely in build-out or evacuation.'
        }
        return
    }
    [pscustomobject]@{
        Cluster         = $_.Name
        TotalCapacityGB = [math]::Round($vsan.TotalCapacityGB,1)
        FreeCapacityGB  = [math]::Round($vsan.FreeSpaceGB,1)
        UsedPercent     = [math]::Round((($vsan.TotalCapacityGB - $vsan.FreeSpaceGB)/$vsan.TotalCapacityGB)*100, 1)
        Note            = ''
    }
}
