# Start of Settings
# End of Settings

$Title          = "Nutanix Cluster Operations Dashboard"
$Header         = "Per-cluster current load + VM count + storage commit"
$Comments       = @"
Single-page operational view of every Nutanix cluster: current CPU + memory utilization, VM count by power state, total storage committed vs cluster capacity, replication factor, encryption status, hypervisor mix.

Mirrors the Pool Operations Dashboard concept on the hypervisor side - lets the operator see live cluster pressure at a glance, not after drilling into Prism.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "Info"
$Recommendation = "Clusters at > 80% CPU OR memory utilization warrant rebalancing or hardware add. Storage commit ratio > 1.5x raw = thin-provision risk under correlated workload spikes."

if (-not (Get-NTNXRestSession)) { return }
$clusters   = @(Get-NTNXCluster)
$hosts      = @(Get-NTNXHost)
$vms        = @(Get-NTNXVM)
$containers = @(Get-NTNXStorageContainer)
if ($clusters.Count -eq 0) { return }

foreach ($c in $clusters) {
    if (-not $c -or -not $c.uuid) { continue }
    $clusterHosts = @($hosts | Where-Object { $_.cluster_reference -and $_.cluster_reference.uuid -eq $c.uuid })
    $clusterVms   = @($vms   | Where-Object { $_.cluster_reference -and $_.cluster_reference.uuid -eq $c.uuid })
    $clusterCtrs  = @($containers | Where-Object { $_.cluster_reference -and $_.cluster_reference.uuid -eq $c.uuid })

    $totalCpuCores = ($clusterHosts | Measure-Object -Property num_cpu_cores -Sum).Sum
    $totalMemMib   = ($clusterHosts | Measure-Object -Property memory_capacity_mib -Sum).Sum
    $vmsOn  = ($clusterVms | Where-Object { $_.power_state -eq 'ON' }).Count
    $vmsOff = ($clusterVms | Where-Object { $_.power_state -eq 'OFF' }).Count
    $vmsSusp = ($clusterVms | Where-Object { $_.power_state -match 'SUSPENDED|PAUSED' }).Count

    $vCPUOn = ($clusterVms | Where-Object { $_.power_state -eq 'ON' } | Measure-Object -Property num_vcpus_per_socket -Sum).Sum
    $vRamMibOn = ($clusterVms | Where-Object { $_.power_state -eq 'ON' } | Measure-Object -Property memory_size_mib -Sum).Sum

    $cap = ($clusterCtrs | Measure-Object -Property advertised_capacity_bytes -Sum).Sum
    $used = 0
    foreach ($ctr in $clusterCtrs) {
        if ($ctr.usage_stats -and $ctr.usage_stats.'storage.usage_bytes') {
            $used += [double]$ctr.usage_stats.'storage.usage_bytes'
        }
    }

    [pscustomobject]@{
        Cluster        = $c.name
        Hosts          = $clusterHosts.Count
        AOSVersion     = if ($c.build) { $c.build.version } else { '' }
        Hypervisor     = if ($c.hypervisor_types) { ($c.hypervisor_types -join ', ') } else { '' }
        RF             = $c.cluster_redundancy_state.current_redundancy_factor
        VMsTotal       = $clusterVms.Count
        VMsOn          = $vmsOn
        VMsOff         = $vmsOff
        VMsSuspended   = $vmsSusp
        TotalCpuCores  = $totalCpuCores
        ConsumedvCPU_On = $vCPUOn
        OvercommitRatioCPU = if ($totalCpuCores -gt 0 -and $vCPUOn) { [math]::Round([double]$vCPUOn / [double]$totalCpuCores, 2) } else { '' }
        TotalRAMGB     = if ($totalMemMib) { [math]::Round($totalMemMib / 1024, 1) } else { '' }
        ConsumedRAMGB_On = if ($vRamMibOn) { [math]::Round($vRamMibOn / 1024, 1) } else { '' }
        ClusterCpuPct  = if ($c.cpu_usage_pct) { $c.cpu_usage_pct } else { '' }
        ClusterMemPct  = if ($c.memory_usage_pct) { $c.memory_usage_pct } else { '' }
        StorageCapTB   = if ($cap) { [math]::Round($cap / 1TB, 2) } else { '' }
        StorageUsedTB  = if ($used) { [math]::Round($used / 1TB, 2) } else { '' }
        StoragePctUsed = if ($cap -gt 0 -and $used) { [math]::Round(($used / $cap) * 100, 1) } else { '' }
        Encryption     = [bool]$c.enable_software_data_encryption
    }
}

$TableFormat = @{
    ClusterCpuPct  = { param($v,$row) if ([double]"$v" -ge 90) { 'bad' } elseif ([double]"$v" -ge 75) { 'warn' } else { '' } }
    ClusterMemPct  = { param($v,$row) if ([double]"$v" -ge 90) { 'bad' } elseif ([double]"$v" -ge 80) { 'warn' } else { '' } }
    StoragePctUsed = { param($v,$row) if ([double]"$v" -ge 90) { 'bad' } elseif ([double]"$v" -ge 80) { 'warn' } else { '' } }
    OvercommitRatioCPU = { param($v,$row) if ([double]"$v" -gt 4) { 'warn' } else { '' } }
}
