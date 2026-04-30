# Start of Settings
$LookbackMinutes  = 60
# Active ballooning or swap-in over this floor (KB) flags the host.
$BalloonKBThreshold = 1024
$SwapInKBThreshold  = 1024
# End of Settings

$Title          = "Host Memory Ballooning / Swapping"
$Header         = "[count] host(s) with active memory pressure"
$Comments       = "VMware KB 1004775: ballooning is the soft signal that the host is running tight on RAM. Swap-in (vmkernel-level) is the hard signal - it causes user-visible 100ms+ stalls. Both are bad for VDI."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "Add hosts to the cluster, evict stale VMs, or right-size oversized VMs. Verify VM reservations / shares match workload tier."

if (-not $Global:VCConnected) { return }

$start = (Get-Date).AddMinutes(-$LookbackMinutes)
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    try {
        $stats = Get-Stat -Entity $h -Stat 'mem.vmmemctl.average','mem.swapinRate.average' `
                          -Start $start -ErrorAction SilentlyContinue
        if (-not $stats) { return }
        $balloon = ($stats | Where-Object { $_.MetricId -eq 'mem.vmmemctl.average' } | Measure-Object Value -Average).Average
        $swapIn  = ($stats | Where-Object { $_.MetricId -eq 'mem.swapinRate.average' } | Measure-Object Value -Average).Average
        if ($balloon -gt $BalloonKBThreshold -or $swapIn -gt $SwapInKBThreshold) {
            [pscustomobject]@{
                Host        = $h.Name
                BalloonKBavg = [int]$balloon
                SwapInKBavg  = [int]$swapIn
                Cluster      = $h.Parent.Name
                MemUsagePct  = [int]$h.MemoryUsageGB / [int]$h.MemoryTotalGB * 100
            }
        }
    } catch { }
}

$TableFormat = @{
    BalloonKBavg = { param($v,$row) if ([int]$v -gt 0) { 'warn' } else { '' } }
    SwapInKBavg  = { param($v,$row) if ([int]$v -gt 0) { 'bad'  } else { '' } }
}
