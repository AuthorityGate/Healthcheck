# Start of Settings
# Minimum surplus headroom: cluster CPU/RAM minus the largest single host
# must still cover current consumption with at least this much buffer.
$MinHeadroomPct = 10
# End of Settings

$Title          = 'Cluster N+1 Capacity Headroom'
$Header         = 'Per-cluster CPU + RAM headroom after worst-case host failure'
$Comments       = "Standard HA design: cluster total minus its largest host (worst-case host failure) should still serve current workload with >= $MinHeadroomPct% buffer. Lists every cluster's current utilization and post-failure surplus so operators can see headroom even when no cluster is in trouble."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.1
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = 'If a cluster shows BELOW THRESHOLD: add capacity, evict workloads, or relax admission control. Verify HA admission-control policy matches your tolerance (Slot vs Percentage vs Dedicated Failover Hosts).'

if (-not $Global:VCConnected) { return }

$clusters = @(Get-Cluster -ErrorAction SilentlyContinue | Sort-Object Name)
if ($clusters.Count -eq 0) {
    [pscustomobject]@{ Note = 'No clusters returned by Get-Cluster.' }
    return
}

foreach ($c in $clusters) {
    $hosts = @($c | Get-VMHost -ErrorAction SilentlyContinue)
    if ($hosts.Count -eq 0) {
        [pscustomobject]@{
            Cluster=$c.Name; Hosts=0; CpuUsedPct=''; MemUsedPct=''; CpuHeadroomPct=''; RamHeadroomPct=''; Threshold="$MinHeadroomPct%"; Status='NO HOSTS'
        }
        continue
    }

    $totalCpuMHz = ($hosts | Measure-Object -Property CpuTotalMhz   -Sum).Sum
    $totalRamMB  = ($hosts | Measure-Object -Property MemoryTotalMB -Sum).Sum
    $maxCpuMHz   = ($hosts | Measure-Object -Property CpuTotalMhz   -Maximum).Maximum
    $maxRamMB    = ($hosts | Measure-Object -Property MemoryTotalMB -Maximum).Maximum
    $usedCpuMHz  = ($hosts | Measure-Object -Property CpuUsageMhz   -Sum).Sum
    $usedRamMB   = ($hosts | Measure-Object -Property MemoryUsageMB -Sum).Sum

    $cpuUsedPct  = if ($totalCpuMHz -gt 0) { [math]::Round(($usedCpuMHz / $totalCpuMHz) * 100, 1) } else { 0 }
    $memUsedPct  = if ($totalRamMB  -gt 0) { [math]::Round(($usedRamMB  / $totalRamMB)  * 100, 1) } else { 0 }

    $survCpu     = $totalCpuMHz - $maxCpuMHz
    $survRam     = $totalRamMB  - $maxRamMB
    $cpuHeadroom = if ($survCpu -gt 0) { [math]::Round((($survCpu - $usedCpuMHz) / $survCpu) * 100, 1) } else { -100 }
    $ramHeadroom = if ($survRam -gt 0) { [math]::Round((($survRam - $usedRamMB)  / $survRam) * 100, 1) } else { -100 }

    $cpuOk = $cpuHeadroom -ge $MinHeadroomPct
    $memOk = $ramHeadroom -ge $MinHeadroomPct
    $status = if ($hosts.Count -lt 2) { 'SINGLE HOST' }
              elseif (-not $cpuOk -and -not $memOk) { 'BELOW (CPU+RAM)' }
              elseif (-not $cpuOk) { 'BELOW (CPU)' }
              elseif (-not $memOk) { 'BELOW (RAM)' }
              else { 'OK' }

    [pscustomobject]@{
        Cluster        = $c.Name
        Hosts          = $hosts.Count
        TotalCpuGHz    = [math]::Round($totalCpuMHz / 1000, 1)
        TotalMemGB     = [math]::Round($totalRamMB  / 1024, 1)
        CpuUsedPct     = $cpuUsedPct
        MemUsedPct     = $memUsedPct
        CpuHeadroomPct = $cpuHeadroom
        RamHeadroomPct = $ramHeadroom
        Threshold      = "$MinHeadroomPct%"
        Status         = $status
    }
}

$TableFormat = @{
    CpuHeadroomPct = { param($v,$row) if ("$v" -ne '' -and [decimal]"$v" -lt 10) { 'bad' } else { '' } }
    RamHeadroomPct = { param($v,$row) if ("$v" -ne '' -and [decimal]"$v" -lt 10) { 'bad' } else { '' } }
    CpuUsedPct     = { param($v,$row) if ("$v" -ne '' -and [decimal]"$v" -ge 80) { 'warn' } else { '' } }
    MemUsedPct     = { param($v,$row) if ("$v" -ne '' -and [decimal]"$v" -ge 80) { 'warn' } else { '' } }
    Status         = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -match 'BELOW|NO HOSTS|SINGLE') { 'warn' } else { '' } }
}
