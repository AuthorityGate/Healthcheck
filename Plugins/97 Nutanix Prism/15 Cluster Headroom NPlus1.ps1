# Start of Settings
# End of Settings

$Title          = "Nutanix Cluster Headroom (N+1)"
$Header         = "Per-cluster compute headroom for one-node failure"
$Comments       = "Models a single-node failure in each cluster: total cluster CPU + memory minus the largest single host = headroom. Compares it to the current aggregate VM resource footprint to determine if the cluster can absorb the failure without overcommit. Critical for VDI clusters where a host failure during business hours = users-can't-login event."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "P1"
$Recommendation = "If 'CanSurviveOneFailure' is False, the cluster is in an N+0 state - any host failure means VM eviction or a power-loss for VMs that can't migrate. Add a host, retire low-priority VMs, or migrate workload off."

if (-not (Get-NTNXRestSession)) { return }
$clusters = @(Get-NTNXCluster)
$hosts    = @(Get-NTNXHost)
if (-not $clusters -or $clusters.Count -eq 0) { return }

foreach ($c in $clusters) {
    if (-not $c -or -not $c.uuid) { continue }
    $clusterHosts = @($hosts | Where-Object { $_.cluster_reference -and $_.cluster_reference.uuid -eq $c.uuid })
    if ($clusterHosts.Count -eq 0) {
        [pscustomobject]@{ Cluster=$c.name; HostCount=0; Note='No hosts visible (possible PE-only with insufficient scope).' }
        continue
    }
    $totalCpuCores = ($clusterHosts | Measure-Object -Property num_cpu_cores -Sum).Sum
    $totalMemMib   = ($clusterHosts | Measure-Object -Property memory_capacity_mib -Sum).Sum
    $largestHostCores = ($clusterHosts | Measure-Object -Property num_cpu_cores -Maximum).Maximum
    $largestHostMem   = ($clusterHosts | Measure-Object -Property memory_capacity_mib -Maximum).Maximum

    $remainingCores = $totalCpuCores - $largestHostCores
    $remainingMemGB = [math]::Round(($totalMemMib - $largestHostMem) / 1024, 1)

    $usedCpuPct = if ($c.cpu_usage_pct) { $c.cpu_usage_pct } else { '' }
    $usedMemPct = if ($c.memory_usage_pct) { $c.memory_usage_pct } else { '' }

    # Rough N+1 viability: if current memory utilization * total mem fits in (total-largest), cluster survives
    $survivesMem = $true
    if ($usedMemPct) {
        $usedMemMib = [math]::Round(($totalMemMib * ([double]$usedMemPct / 100)), 0)
        $survivesMem = ($usedMemMib -le ($totalMemMib - $largestHostMem))
    }

    [pscustomobject]@{
        Cluster                = $c.name
        HostCount              = $clusterHosts.Count
        TotalCpuCores          = $totalCpuCores
        TotalMemoryGB          = [math]::Round($totalMemMib / 1024, 1)
        AfterOneFailureCores   = $remainingCores
        AfterOneFailureMemGB   = $remainingMemGB
        CurrentCpuPctUsed      = $usedCpuPct
        CurrentMemPctUsed      = $usedMemPct
        CanSurviveOneFailure   = $survivesMem
    }
}

$TableFormat = @{
    CanSurviveOneFailure = { param($v,$row) if ($v -eq $true) { 'ok' } elseif ($v -eq $false) { 'bad' } else { '' } }
    HostCount            = { param($v,$row) if ([int]"$v" -lt 3) { 'bad' } elseif ([int]"$v" -lt 4) { 'warn' } else { '' } }
}
