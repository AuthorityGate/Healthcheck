# Start of Settings
# Cap on pools enriched per run to keep large estates from blowing out the report.
$MaxPools = 250
# End of Settings

$Title          = "Pool Operations Dashboard"
$Header         = "[count] pool(s) - per-pool live capacity + connection summary"
$Comments       = @"
Single-page operational view of every desktop pool. For each pool:

- Configured maximum machines vs currently provisioned
- Spare capacity setting + headroom
- Machine state buckets (AVAILABLE, CONNECTED, DISCONNECTED, ERROR, PROVISIONING, CUSTOMIZING)
- Currently connected user sessions
- Currently disconnected sessions (sessions held but not in use)
- 24-hour session-count trend bucket
- Provisioning template (parent VM + snapshot)

This is the 'capacity right now' view operations needs. Joins Horizon REST inventory + monitor + per-pool usage + sessions-by-pool so you don't have to cross-reference six different Horizon Console tabs.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = "30 Desktop Pools"
$Severity       = "Info"
$Recommendation = "Pools at MaxConfigured / 90% need expansion. Pools where Errored count > 5% of Provisioned indicate provisioning failures that should be drained + investigated. Disconnected sessions held > 24h consume capacity unnecessarily; tighten the per-pool idle / disconnect policy."

if (-not (Get-HVRestSession)) { return }
$pools = @(Get-HVDesktopPool)
if ($pools.Count -eq 0) { return }
if ($pools.Count -gt $MaxPools) { $pools = $pools | Select-Object -First $MaxPools }

# Pull all sessions ONCE (cheaper than per-pool /sessions queries)
$allSessions = @()
try { $allSessions = @(Get-HVSession) } catch { }

# Helper: walk dotted property paths and return first non-null match. When
# the resolved value comes back as System.Object[] (the path landed on an
# array-typed field), unwrap to its first scalar - downstream callers cast
# to [int]/[double] which throws "Cannot convert System.Object[] to Int32"
# when fed an array.
function Get-PoolValue {
    param($Pool, [string[]]$Paths)
    foreach ($p in $Paths) {
        $segments = $p -split '\.'
        $cur = $Pool; $ok = $true
        foreach ($s in $segments) { if ($null -eq $cur) { $ok=$false; break } ; try { $cur = $cur.$s } catch { $ok=$false; break } ; if ($null -eq $cur) { $ok=$false; break } }
        if ($ok -and $cur) {
            if ($cur -is [System.Array]) { $cur = @($cur)[0] }
            if ($null -ne $cur -and "$cur" -ne '') { return $cur }
        }
    }
    return $null
}

function _ToInt {
    param($V)
    if ($null -eq $V) { return $null }
    if ($V -is [System.Array]) { $V = @($V)[0] }
    try { return [int]"$V" } catch { return $null }
}

foreach ($p in $pools) {
    if (-not $p) { continue }
    $poolId = $null
    foreach ($k in @('id','uuid','pool_id')) {
        if ($p.PSObject.Properties[$k] -and $p.$k) { $poolId = [string]$p.$k; break }
    }
    if (-not $poolId -and $p.metadata -and $p.metadata.uuid) { $poolId = [string]$p.metadata.uuid }

    $detail = $null
    if ($poolId) { try { $detail = Get-HVDesktopPoolDetail -Id $poolId } catch { } }
    if (-not $detail) { $detail = $p }

    $machines = @()
    if ($poolId) { try { $machines = @(Get-HVDesktopPoolMachine -Id $poolId) } catch { } }

    $usage = $null
    if ($poolId) { try { $usage = Get-HVDesktopPoolUsage -Id $poolId } catch { } }

    # Per-pool session counts via the global sessions list
    $poolSessions = @($allSessions | Where-Object { ($_.desktop_pool_id -eq $poolId) -or ($_.pool_id -eq $poolId) -or ($_.pool_name -eq $p.name) })
    $connectedSessions    = @($poolSessions | Where-Object { $_.session_state -match 'CONNECTED|ACTIVE' }).Count
    $disconnectedSessions = @($poolSessions | Where-Object { $_.session_state -match 'DISCONNECTED|IDLE' }).Count

    $maxMachines = Get-PoolValue -Pool $detail -Paths @(
        'provisioning_settings.max_number_of_machines',
        'vmware_provisioning_settings.max_number_of_machines',
        'nutanix_provisioning_settings.max_number_of_machines',
        'max_number_of_machines'
    )
    $spare = Get-PoolValue -Pool $detail -Paths @(
        'provisioning_settings.spare_machines',
        'vmware_provisioning_settings.spare_machines',
        'spare_machines','min_ready_vms_on_vcomposer_maintenance'
    )
    $parentVm = Get-PoolValue -Pool $detail -Paths @(
        'provisioning_settings.parent_vm_path',
        'vmware_provisioning_settings.parent_vm_path',
        'nutanix_provisioning_settings.parent_vm_path',
        'parent_vm_path'
    )
    $snapshot = Get-PoolValue -Pool $detail -Paths @(
        'provisioning_settings.base_snapshot_path',
        'vmware_provisioning_settings.base_snapshot_path',
        'nutanix_provisioning_settings.base_snapshot_path',
        'base_snapshot_path'
    )

    $available    = ($machines | Where-Object { $_.state -eq 'AVAILABLE' }).Count
    $connectedM   = ($machines | Where-Object { $_.state -match 'CONNECTED|IN_USE' }).Count
    $disconnectedM = ($machines | Where-Object { $_.state -match 'DISCONNECTED' }).Count
    $errored      = ($machines | Where-Object { $_.state -match 'ERROR|UNREACHABLE|MAINTENANCE' }).Count
    $provisioning = ($machines | Where-Object { $_.state -match 'PROVISIONING|CUSTOMIZING|STARTING' }).Count

    $maxInt = _ToInt $maxMachines
    $pctUtil = $null
    if ($maxInt -and $maxInt -gt 0) {
        $pctUtil = [math]::Round(($machines.Count / $maxInt) * 100, 1)
    }

    [pscustomobject]@{
        Pool            = if ($p.name) { $p.name } else { $p.display_name }
        Type            = $p.type
        Source          = $p.source
        MaxMachines     = if ($null -ne $maxInt) { $maxInt } else { '' }
        Provisioned     = $machines.Count
        PctOfMax        = $pctUtil
        Spare           = if ($spare -is [System.Array]) { @($spare)[0] } else { $spare }
        Available       = $available
        ConnectedM      = $connectedM
        DisconnectedM   = $disconnectedM
        Provisioning    = $provisioning
        Errored         = $errored
        ActiveSessions  = $connectedSessions
        DisconnectedSessions = $disconnectedSessions
        TotalSessions   = $poolSessions.Count
        ParentVM        = if ($parentVm) { Split-Path -Leaf -Path ([string]$parentVm) } else { '' }
        Snapshot        = if ($snapshot) { Split-Path -Leaf -Path ([string]$snapshot) } else { '' }
    }
}

$TableFormat = @{
    PctOfMax = { param($v,$row) if ([double]"$v" -ge 90) { 'bad' } elseif ([double]"$v" -ge 75) { 'warn' } else { '' } }
    Errored  = { param($v,$row) if ([int]"$v" -gt 5) { 'bad' } elseif ([int]"$v" -gt 0) { 'warn' } else { '' } }
    DisconnectedSessions = { param($v,$row) if ([int]"$v" -gt 50) { 'warn' } else { '' } }
}
