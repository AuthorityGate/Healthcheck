# Start of Settings
# Protect against runaway scans on large estates - cap pools enriched per run.
$MaxPools = 200
# End of Settings

$Title          = "Desktop Pool Deep Detail"
$Header         = "[count] pool(s) with full configuration captured"
$Comments       = @"
For every pool we pull the complete Horizon REST detail block: provisioning template, parent VM + snapshot, customization spec, datastores, max VMs, machine state buckets, current entitlement counts, push-image state. This is the data needed for upgrade planning, cohort capacity-modeling, and identifying pools that share a parent VM (single-image risk).
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "30 Desktop Pools"
$Severity       = "Info"
$Recommendation = "Pools sharing a parent VM are coupled to one image lifecycle. Pools without a customization spec, missing parent snapshot, or with empty entitlement set should be reviewed. Floating pools without 'delete on logoff' = sticky session risk."

if (-not (Get-HVRestSession)) { return }
$pools = @(Get-HVDesktopPool)
if (-not $pools) { return }
if ($pools.Count -gt $MaxPools) { $pools = $pools | Select-Object -First $MaxPools }

# Helper: try several common nested-paths for provisioning / customization
# settings. Different MP plugins (vSphere instant clone, vSphere full
# clone, Nutanix AHV instant clone, Azure WVD legacy) emit data under
# different keys. We probe the most-common ones in order and return the
# first non-null match. Plugins reading a flat property after this never
# need to know which MP backed the pool.
function Get-HVPoolNestedValue {
    param($Pool, [string[]]$Paths)
    foreach ($p in $Paths) {
        $segments = $p -split '\.'
        $cur = $Pool
        $ok = $true
        foreach ($s in $segments) {
            if ($null -eq $cur) { $ok = $false; break }
            try { $cur = $cur.$s } catch { $ok = $false; break }
            if ($null -eq $cur) { $ok = $false; break }
        }
        if ($ok -and $cur) { return $cur }
    }
    return $null
}

foreach ($p in $pools) {
    # Resolve a usable id - try id, uuid, metadata.uuid, pool_id. Don't
    # silently skip pools whose id field landed under a different name.
    $poolId = $null
    foreach ($k in @('id','uuid','pool_id')) {
        if ($p.PSObject.Properties[$k] -and $p.$k) { $poolId = [string]$p.$k; break }
    }
    if (-not $poolId -and $p.metadata -and $p.metadata.uuid) { $poolId = [string]$p.metadata.uuid }

    $detail = $null
    if ($poolId) {
        try { $detail = Get-HVDesktopPoolDetail -Id $poolId } catch { }
    }
    if (-not $detail) { $detail = $p }

    $machines = @()
    if ($poolId) {
        try { $machines = @(Get-HVDesktopPoolMachine -Id $poolId) } catch { }
    }
    $usage = $null
    if ($poolId) {
        try { $usage = Get-HVDesktopPoolUsage -Id $poolId } catch { }
    }

    # Try multiple nested paths for provisioning + customization settings.
    # Nutanix-backed pools nest under nutanix_*_settings; vSphere uses
    # provisioning_settings; some 2206 builds use vmware_provisioning_settings.
    $parentVM = Get-HVPoolNestedValue -Pool $detail -Paths @(
        'provisioning_settings.parent_vm_path',
        'vmware_provisioning_settings.parent_vm_path',
        'nutanix_provisioning_settings.parent_vm_path',
        'parent_vm_path'
    )
    $snapshot = Get-HVPoolNestedValue -Pool $detail -Paths @(
        'provisioning_settings.base_snapshot_path',
        'vmware_provisioning_settings.base_snapshot_path',
        'nutanix_provisioning_settings.base_snapshot_path',
        'base_snapshot_path'
    )
    $maxMachines = Get-HVPoolNestedValue -Pool $detail -Paths @(
        'provisioning_settings.max_number_of_machines',
        'vmware_provisioning_settings.max_number_of_machines',
        'nutanix_provisioning_settings.max_number_of_machines',
        'max_number_of_machines'
    )
    $custSpec = Get-HVPoolNestedValue -Pool $detail -Paths @(
        'customization_settings.specification_name',
        'vmware_customization_settings.specification_name',
        'nutanix_customization_settings.specification_name',
        'specification_name'
    )
    $adContainer = Get-HVPoolNestedValue -Pool $detail -Paths @(
        'customization_settings.ad_container_rdn',
        'vmware_customization_settings.ad_container_rdn',
        'nutanix_customization_settings.ad_container_rdn',
        'ad_container_rdn'
    )
    $provType = if ($detail.provisioning_type) { $detail.provisioning_type } else {
        Get-HVPoolNestedValue -Pool $detail -Paths @('vmware_provisioning_settings.provisioning_type','nutanix_provisioning_settings.provisioning_type')
    }
    # Hypervisor / MP hint - vSphere vs AHV / Nutanix vs VirtualCenter
    $mp = Get-HVPoolNestedValue -Pool $detail -Paths @(
        'virtual_center_managed','vsphere_managed','provisioning_settings.virtual_center_managed'
    )
    $hypervisorTag = if ($detail.PSObject.Properties['nutanix_provisioning_settings'] -and $detail.nutanix_provisioning_settings) { 'AHV (Nutanix)' }
                     elseif ($detail.PSObject.Properties['vmware_provisioning_settings'] -and $detail.vmware_provisioning_settings) { 'vSphere' }
                     elseif ($mp) { 'vSphere' }
                     else { '' }
    $deleteOnLogoff = $false
    try {
        $deleteOnLogoff = [bool](Get-HVPoolNestedValue -Pool $p -Paths @(
            'session_settings.delete_in_progress_machines_on_logoff',
            'delete_in_progress_machines_on_logoff',
            'session_settings.delete_on_logoff'
        ))
    } catch { }

    [pscustomobject]@{
        Pool          = if ($p.name) { $p.name } elseif ($p.display_name) { $p.display_name } else { $poolId }
        PoolId        = $poolId
        Type          = $p.type
        Source        = $p.source
        Hypervisor    = $hypervisorTag
        ProvisionType = $provType
        ParentVM      = $parentVM
        Snapshot      = $snapshot
        CustomSpec    = $custSpec
        AdContainer   = $adContainer
        MaxMachines   = $maxMachines
        MachineCount  = $machines.Count
        Available     = ($machines | Where-Object { $_.state -eq 'AVAILABLE' }).Count
        Connected     = ($machines | Where-Object { $_.state -eq 'CONNECTED' }).Count
        Errored       = ($machines | Where-Object { $_.state -match 'ERROR|UNREACHABLE' }).Count
        Sessions      = if ($usage -and $usage.num_machines) { $usage.num_machines - $usage.num_available_machines } else { '' }
        DeleteOnLogoff = $deleteOnLogoff
    }
}
