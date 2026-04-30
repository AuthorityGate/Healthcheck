# Start of Settings
# Lookback window for the worst-case calculation. vCenter retains 30-min
# rollup data for ~30 days by default (Statistics Levels), so a 30-day
# query is the deepest reliable granularity without changing vC settings.
$LookbackDays = 30
# Granularity (vCenter rollup level) - 30 minutes is the default for the
# "Past Month" historical stats interval. 5 minutes only goes back ~1 day.
$IntervalMinutes = 30
# Per-host stats query timeout in seconds; large clusters with shallow
# performance retention can time out. Caller can lift via $Global:.
if (-not $Global:VCStat30dTimeout) { $Global:VCStat30dTimeout = 90 }
# End of Settings

$Title          = "ESXi Host - 30 Day CPU / Memory Peak"
$Header         = "[count] host(s) profiled (current + 30 day peak)"
$Comments       = @"
For every connected ESXi host this plugin reports:
- Current CPU and memory utilization (real-time sample at scan time)
- Worst-case CPU and memory utilization over the last $LookbackDays days, pulled from vCenter performance rollups, with the exact timestamp of the peak
This identifies hosts that are sized for averages but cannot absorb peaks (login storms, antivirus scans, monthly batch jobs). Source: vCenter performance manager 30-min rollups (Statistics Level 1 or higher; see KB 2150794 if values look truncated).
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "Info"
$Recommendation = @"
Hosts whose 30-day CPU peak > 85% or memory peak > 90% should be considered capacity-constrained. Right-size oversized VMs, migrate workload to peers, or add hosts to the cluster. If the peak occurred at a known maintenance window (e.g., AV full scan), schedule it outside login hours instead. Persistently high peaks combined with VM CPU Ready outliers (see plugin 13) signal real CPU oversubscription.
"@

if (-not $Global:VCConnected) {
    [pscustomobject]@{ Host='(no vCenter)'; Note='Connect a vCenter in the runner to enable host peak metrics.' }
    return
}

$start = (Get-Date).AddDays(-$LookbackDays)
$now   = Get-Date
$hosts = @(Get-VMHost -ErrorAction SilentlyContinue)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Host='(none)'; Note='vCenter has no hosts visible to this account.' }
    return
}

foreach ($h in $hosts) {
    if (-not $h) { continue }
    if ($h.ConnectionState -ne 'Connected' -and $h.ConnectionState -ne 'Maintenance') {
        [pscustomobject]@{
            Host             = $h.Name
            ConnectionState  = [string]$h.ConnectionState
            CpuPctNow        = $null; MemPctNow      = $null
            CpuPctPeak30d    = $null; CpuPeakAt      = $null
            MemPctPeak30d    = $null; MemPeakAt      = $null
            CpuMhzUsedNow    = $null; CpuMhzCapacity = $null
            MemUsedGBNow     = $null; MemTotalGB     = $null
            Note             = "Host not Connected; skipped peak query."
        }
        continue
    }

    # Current snapshot - directly from the host object so it's always available
    $cpuMhzUsed = [int]$h.CpuUsageMhz
    $cpuMhzCap  = [int]$h.CpuTotalMhz
    $cpuPctNow  = if ($cpuMhzCap -gt 0) { [math]::Round(($cpuMhzUsed / $cpuMhzCap) * 100, 1) } else { $null }
    $memUsedGB  = [math]::Round([double]$h.MemoryUsageGB, 1)
    $memTotalGB = [math]::Round([double]$h.MemoryTotalGB, 1)
    $memPctNow  = if ($memTotalGB -gt 0) { [math]::Round(($memUsedGB / $memTotalGB) * 100, 1) } else { $null }

    # 30-day rollup - cpu.usage.average + mem.usage.average are stored as %
    # already (in 100ths-of-percent), so divide by 100 to get a percentage.
    $cpuPeak = $null; $cpuPeakAt = $null
    $memPeak = $null; $memPeakAt = $null
    $note    = ''
    try {
        $stats = Get-Stat -Entity $h -Stat 'cpu.usage.average','mem.usage.average' `
                          -Start $start -Finish $now -IntervalMins $IntervalMinutes `
                          -ErrorAction Stop
        if ($stats) {
            $cpuS = $stats | Where-Object { $_.MetricId -eq 'cpu.usage.average' }
            $memS = $stats | Where-Object { $_.MetricId -eq 'mem.usage.average' }
            if ($cpuS) {
                $top = $cpuS | Sort-Object Value -Descending | Select-Object -First 1
                $cpuPeak   = [math]::Round([double]$top.Value / 100, 1)
                $cpuPeakAt = $top.Timestamp.ToString('yyyy-MM-dd HH:mm zzz')
            }
            if ($memS) {
                $top = $memS | Sort-Object Value -Descending | Select-Object -First 1
                $memPeak   = [math]::Round([double]$top.Value / 100, 1)
                $memPeakAt = $top.Timestamp.ToString('yyyy-MM-dd HH:mm zzz')
            }
            if (-not $cpuPeak -and -not $memPeak) {
                $note = "No rollup data in window; verify Statistics Level (vC -> Settings -> Statistics)."
            }
        } else {
            $note = "No samples returned. Statistics Level 1+ for 30-day window required."
        }
    } catch {
        $note = "Stat query failed: $($_.Exception.Message)"
    }

    [pscustomobject]@{
        Host             = $h.Name
        Cluster          = if ($h.Parent) { [string]$h.Parent.Name } else { '' }
        ConnectionState  = [string]$h.ConnectionState
        CpuPctNow        = $cpuPctNow
        CpuPctPeak30d    = $cpuPeak
        CpuPeakAt        = $cpuPeakAt
        MemPctNow        = $memPctNow
        MemPctPeak30d    = $memPeak
        MemPeakAt        = $memPeakAt
        CpuMhzUsedNow    = $cpuMhzUsed
        CpuMhzCapacity   = $cpuMhzCap
        MemUsedGBNow     = $memUsedGB
        MemTotalGB       = $memTotalGB
        Note             = $note
    }
}

$TableFormat = @{
    CpuPctNow     = { param($v,$row) if ([double]"$v" -ge 90) { 'bad' } elseif ([double]"$v" -ge 75) { 'warn' } else { '' } }
    MemPctNow     = { param($v,$row) if ([double]"$v" -ge 90) { 'bad' } elseif ([double]"$v" -ge 80) { 'warn' } else { '' } }
    CpuPctPeak30d = { param($v,$row) if ([double]"$v" -ge 95) { 'bad' } elseif ([double]"$v" -ge 85) { 'warn' } else { '' } }
    MemPctPeak30d = { param($v,$row) if ([double]"$v" -ge 95) { 'bad' } elseif ([double]"$v" -ge 90) { 'warn' } else { '' } }
}
