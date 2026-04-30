# Start of Settings
$LookbackDays = 30
$IntervalSecs = 1800   # 30-min rollup matches Prism default retention
# End of Settings

$Title          = "AHV Host - 30 Day CPU / Memory Peak"
$Header         = "[count] host(s) profiled (current + 30 day peak)"
$Comments       = @"
Mirrors the ESXi 30-day Peak plugin for Nutanix. Pulls the rollup curve for every host and reports both the current sample and the worst-case sample over the last $LookbackDays days, with the timestamp of the peak. Source: hypervisor_cpu_usage_ppm + hypervisor_memory_usage_ppm via /hosts/<uuid>/stats. ppm = parts per million; the module auto-converts to percent.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "Info"
$Recommendation = "Hosts with 30-day CPU peak > 85% or memory peak > 90% are oversubscribed at peak. Migrate VDI workload, right-size oversized VMs, or add nodes via LCM. Persistent peaks combined with VM oplog flood alerts mean storage IOPS is the bottleneck not CPU."

if (-not (Get-NTNXRestSession)) { return }
$hosts = @(Get-NTNXHost)
if (-not $hosts) {
    [pscustomobject]@{ Note='No hosts visible to this account.' }
    return
}

foreach ($h in $hosts) {
    if (-not $h -or -not $h.uuid) { continue }
    $cpuPeak = $null; $cpuPeakAt = $null; $memPeak = $null; $memPeakAt = $null; $note = ''

    try {
        $cpuStat = Get-NTNXHostStat -Uuid $h.uuid -Metric 'hypervisor_cpu_usage_ppm' -LookbackDays $LookbackDays -IntervalSecs $IntervalSecs
        $memStat = Get-NTNXHostStat -Uuid $h.uuid -Metric 'hypervisor_memory_usage_ppm' -LookbackDays $LookbackDays -IntervalSecs $IntervalSecs
        if ($cpuStat -and $cpuStat.stats_specific_responses) {
            $samples = @($cpuStat.stats_specific_responses[0].values)
            if ($samples.Count -gt 0) {
                $top = $samples | Sort-Object value -Descending | Select-Object -First 1
                $cpuPeak   = [math]::Round([double]$top.value / 10000, 1)
                $cpuPeakAt = [datetimeoffset]::FromUnixTimeMilliseconds([long]$top.timestamp_in_usecs / 1000).ToLocalTime().ToString('yyyy-MM-dd HH:mm zzz')
            }
        }
        if ($memStat -and $memStat.stats_specific_responses) {
            $samples = @($memStat.stats_specific_responses[0].values)
            if ($samples.Count -gt 0) {
                $top = $samples | Sort-Object value -Descending | Select-Object -First 1
                $memPeak   = [math]::Round([double]$top.value / 10000, 1)
                $memPeakAt = [datetimeoffset]::FromUnixTimeMilliseconds([long]$top.timestamp_in_usecs / 1000).ToLocalTime().ToString('yyyy-MM-dd HH:mm zzz')
            }
        }
        if (-not $cpuPeak -and -not $memPeak) { $note = 'No rollup samples returned (Stats Manager may have just started, or retention is < 30 days).' }
    } catch { $note = "Stat query failed: $($_.Exception.Message)" }

    [pscustomobject]@{
        Host           = $h.name
        Cluster        = if ($h.cluster_reference) { $h.cluster_reference.name } else { '' }
        CpuPctNow      = $h.cpu_usage_pct
        CpuPctPeak30d  = $cpuPeak
        CpuPeakAt      = $cpuPeakAt
        MemPctNow      = $h.memory_usage_pct
        MemPctPeak30d  = $memPeak
        MemPeakAt      = $memPeakAt
        Note           = $note
    }
}

$TableFormat = @{
    CpuPctNow     = { param($v,$row) if ([double]"$v" -ge 90) { 'bad' } elseif ([double]"$v" -ge 75) { 'warn' } else { '' } }
    MemPctNow     = { param($v,$row) if ([double]"$v" -ge 90) { 'bad' } elseif ([double]"$v" -ge 80) { 'warn' } else { '' } }
    CpuPctPeak30d = { param($v,$row) if ([double]"$v" -ge 95) { 'bad' } elseif ([double]"$v" -ge 85) { 'warn' } else { '' } }
    MemPctPeak30d = { param($v,$row) if ([double]"$v" -ge 95) { 'bad' } elseif ([double]"$v" -ge 90) { 'warn' } else { '' } }
}
