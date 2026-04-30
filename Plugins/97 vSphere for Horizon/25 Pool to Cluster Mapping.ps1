# Start of Settings
# End of Settings

$Title          = "Pool to Cluster Mapping (Capacity Footprint)"
$Header         = "Per-cluster Horizon footprint - which pools live where, and what fraction of cluster capacity each consumes"
$Comments       = "Cross-references each Horizon pool's parent VM with its host + cluster (via vCenter). Surfaces: per cluster, which pools land there + how many machines + total CPU + RAM that pool consumes from the cluster. Used for capacity planning - 'if I retire cluster X, where do these pools go'."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "Info"
$Recommendation = "Pools concentrated on a single cluster = single point of capacity failure. Consider distributing critical pools across clusters via DRS rules or pool-cluster placement settings. Pools whose machines are scattered across multiple clusters = clone-target inconsistency; verify placement intent."

if (-not $Global:VCConnected) { return }
if (-not (Get-HVRestSession)) { return }

$pools = @(Get-HVDesktopPool)
if ($pools.Count -eq 0) { return }

$clusterMap = @{}
foreach ($pool in $pools) {
    if (-not $pool.id) { continue }
    $machines = @()
    try { $machines = @(Get-HVDesktopPoolMachine -Id $pool.id) } catch { }
    if ($machines.Count -eq 0) { continue }
    foreach ($m in $machines) {
        if (-not $m.dns_name -and -not $m.name) { continue }
        $vmName = if ($m.name) { $m.name } else { $m.dns_name -replace '\..+$','' }
        $vm = $null
        try { $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { }
        if (-not $vm) { continue }
        $cluster = if ($vm.VMHost -and $vm.VMHost.Parent) { [string]$vm.VMHost.Parent.Name } else { '(unknown)' }
        if (-not $clusterMap.ContainsKey($cluster)) { $clusterMap[$cluster] = @{} }
        if (-not $clusterMap[$cluster].ContainsKey($pool.name)) {
            $clusterMap[$cluster][$pool.name] = @{ Count=0; CpuSum=0; MemSum=0 }
        }
        $clusterMap[$cluster][$pool.name].Count++
        $clusterMap[$cluster][$pool.name].CpuSum += [int]$vm.NumCpu
        $clusterMap[$cluster][$pool.name].MemSum += [double]$vm.MemoryGB
    }
}

if ($clusterMap.Count -eq 0) {
    [pscustomobject]@{ Note = 'No pool-machine-cluster relationships could be resolved (Horizon-side machine names did not match any vCenter VM).' }
    return
}

foreach ($cluster in ($clusterMap.Keys | Sort-Object)) {
    foreach ($poolName in ($clusterMap[$cluster].Keys | Sort-Object)) {
        $entry = $clusterMap[$cluster][$poolName]
        [pscustomobject]@{
            Cluster      = $cluster
            Pool         = $poolName
            VMCount      = $entry.Count
            TotalvCPU    = $entry.CpuSum
            TotalRAMGB   = [math]::Round($entry.MemSum, 1)
        }
    }
}
