# Start of Settings
# End of Settings

$Title          = "Nutanix Cluster Inventory"
$Header         = "[count] cluster(s) registered with this Prism target"
$Comments       = "Prism Central federates across every registered cluster; PE returns the single hosting cluster. Surfaces AOS version, hypervisor type (AHV / ESXi / Hyper-V), node count, redundancy factor, capacity, and whether the cluster is in maintenance / locked / lifecycle states."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "Info"
$Recommendation = "Mixed AOS versions across a federation are a P2 - upgrade lagging clusters to current LTS within the maintenance window. RF=2 with < 5 nodes risks data loss on simultaneous host + disk failures; recommend RF=3 for clusters with > 7 nodes hosting VDI workload."

if (-not (Get-NTNXRestSession)) { return }
$clusters = @(Get-NTNXCluster)
if (-not $clusters) {
    [pscustomobject]@{ Note='No clusters returned. Service account may lack view_cluster permission.' }
    return
}

foreach ($c in $clusters) {
    [pscustomobject]@{
        Name             = $c.name
        Hypervisor       = if ($c.hypervisor_types) { ($c.hypervisor_types -join ', ') } else { '' }
        AOSVersion       = if ($c.build) { $c.build.version } else { '' }
        FullVersion      = if ($c.build) { $c.build.full_version } else { '' }
        NodeCount        = if ($c.nodes) { @($c.nodes.host_reference_list).Count } else { '' }
        RedundancyFactor = $c.cluster_redundancy_state.current_redundancy_factor
        DesiredRF        = $c.cluster_redundancy_state.desired_redundancy_factor
        Domain           = $c.domain_awareness_level
        Timezone         = $c.timezone
        ExternalIP       = $c.external_ip
        InternalSubnet   = $c.internal_subnet
        EnableSoftwareEncryption = [bool]$c.enable_software_data_encryption
        IsAvailable      = [bool]$c.is_available
        State            = if ($c.state) { $c.state } else { $c.operation_mode }
    }
}

$TableFormat = @{
    State            = { param($v,$row) if ($v -match 'NORMAL|RUNNING') { 'ok' } elseif ($v -match 'MAINTENANCE|UPGRADE') { 'warn' } elseif ($v) { 'bad' } else { '' } }
    RedundancyFactor = { param($v,$row) if ([int]"$v" -lt 2) { 'bad' } elseif ([int]"$v" -eq 2) { 'warn' } else { 'ok' } }
    IsAvailable      = { param($v,$row) if ($v -eq $true) { 'ok' } else { 'bad' } }
}
