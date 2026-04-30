# Start of Settings
# End of Settings

$Title          = "AHV Host Inventory + Build"
$Header         = "[count] AHV / hypervisor host(s) profiled"
$Comments       = "Per-host vendor / model / CPU SKU / cores / RAM / NIC count, AOS-side hypervisor version, BMC + IPMI build. Equivalent to ESXi Build and Patch Currency + Hardware Inventory but for Nutanix nodes."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "Info"
$Recommendation = "Mixed CPU SKUs across a cluster constrain VM live-migration; check EVC-equivalent setting (Cluster Redundancy + CPU Compatibility). BMC firmware older than 18 months is a CVE risk - schedule LCM upgrade."

if (-not (Get-NTNXRestSession)) { return }
$hosts = @(Get-NTNXHost)
if (-not $hosts) {
    [pscustomobject]@{ Note='No hosts returned. Check view_host permission.' }
    return
}

foreach ($h in $hosts) {
    [pscustomobject]@{
        Name             = $h.name
        Cluster          = if ($h.cluster_reference) { $h.cluster_reference.name } else { '' }
        HypervisorType   = $h.hypervisor.hypervisor_type
        HypervisorVer    = $h.hypervisor.hypervisor_full_name
        CVMIP            = if ($h.controller_vm) { $h.controller_vm.ip } else { '' }
        HostIP           = $h.hypervisor.ip
        IPMIIP           = $h.ipmi.ip
        Sockets          = $h.num_cpu_sockets
        Cores            = $h.num_cpu_cores
        Threads          = $h.num_cpu_threads
        CPUFrequencyHz   = $h.cpu_frequency_hz
        CPUModel         = $h.cpu_model
        RAMGB            = if ($h.memory_capacity_mib) { [math]::Round([double]$h.memory_capacity_mib / 1024, 0) } else { '' }
        BlockSerial      = $h.block.block_serial_number
        BlockModel       = $h.block.block_model
        Vendor           = $h.host_type
        BootTime         = if ($h.boot_time_usecs) { [datetimeoffset]::FromUnixTimeMilliseconds([long]$h.boot_time_usecs / 1000).ToLocalTime().ToString('yyyy-MM-dd HH:mm') } else { '' }
        FailoverCluster  = $h.failover_cluster.name
        State            = $h.state
    }
}

$TableFormat = @{
    State = { param($v,$row) if ($v -match 'NORMAL|HEALTHY|UP') { 'ok' } elseif ($v -match 'MAINTENANCE|UPGRADE') { 'warn' } elseif ($v) { 'bad' } else { '' } }
}
