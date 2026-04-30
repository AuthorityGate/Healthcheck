# Start of Settings
# End of Settings

$Title          = 'Host Memory Inventory'
$Header         = 'Per-host total memory + module count'
$Comments       = 'Total RAM + DIMM module count + DIMM model when exposed by hardware. NUMA node count gives a hint at sizing for VMs.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'Info'
$Recommendation = 'Maintain memory-balance across NUMA nodes; symmetric DIMM population maximizes performance.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_.ExtensionData
    [pscustomobject]@{
        Host          = $_.Name
        TotalMemoryGB = [math]::Round($h.Hardware.MemorySize / 1GB, 1)
        NumaNodes     = if ($h.Hardware.NumaInfo) { @($h.Hardware.NumaInfo.NumaNode).Count } else { 0 }
        MemoryUsageGB = [math]::Round($_.MemoryUsageGB, 1)
        UsagePercent  = if ($_.MemoryTotalGB -gt 0) { [math]::Round(($_.MemoryUsageGB / $_.MemoryTotalGB) * 100, 1) } else { 0 }
    }
}
