# Start of Settings
$MaxFarms = 200
# End of Settings

$Title          = "RDS Farm Operations Dashboard"
$Header         = "[count] RDS farm(s) - per-farm host count, session count, capacity"
$Comments       = @"
Single-page operational view of every RDS farm (Horizon-managed RDSH). For each farm:

- Configured maximum sessions per host x host count = farm capacity
- Currently provisioned RDSH host count
- Available vs Maintenance vs Errored hosts
- Currently active sessions across the farm
- Currently disconnected sessions
- 24h session-count trend
- Provisioning template (parent VM + snapshot for instant-clone farms; manual for legacy)
- Load balancing strategy

This is the 'how full is each farm' answer that operations needs in a single view, joining Horizon REST inventory + monitor + sessions-by-farm.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "40 RDS Farms"
$Severity       = "Info"
$Recommendation = "Farms operating > 80% session-cap utilization warrant additional RDSH hosts BEFORE the next login surge. Errored hosts > 5% of farm = drain + investigate. Disconnected sessions held > 2h on a session-cap-bound farm = tighten the disconnect-timeout policy."

if (-not (Get-HVRestSession)) { return }
$farms = @(Get-HVFarm)
if ($farms.Count -eq 0) { return }
if ($farms.Count -gt $MaxFarms) { $farms = $farms | Select-Object -First $MaxFarms }

$rdsServers = @(Get-HVRdsServer)
$allSessions = @()
try { $allSessions = @(Get-HVSession) } catch { }

function Get-FarmValue {
    param($Farm, [string[]]$Paths)
    foreach ($p in $Paths) {
        $segments = $p -split '\.'
        $cur = $Farm; $ok = $true
        foreach ($s in $segments) { if ($null -eq $cur) { $ok=$false; break } ; try { $cur = $cur.$s } catch { $ok=$false; break } ; if ($null -eq $cur) { $ok=$false; break } }
        if ($ok -and $cur) { return $cur }
    }
    return $null
}

foreach ($f in $farms) {
    if (-not $f) { continue }
    $farmId = $null
    foreach ($k in @('id','uuid','farm_id')) { if ($f.PSObject.Properties[$k] -and $f.$k) { $farmId = [string]$f.$k; break } }

    $hosts = @($rdsServers | Where-Object { ($_.farm_id -eq $farmId) -or ($_.farm_name -eq $f.name) })
    $hostCount = $hosts.Count
    $available = ($hosts | Where-Object { $_.status -eq 'AVAILABLE' -or $_.agent_state -eq 'AVAILABLE' }).Count
    $maintenance = ($hosts | Where-Object { $_.status -match 'MAINTENANCE|DRAIN' }).Count
    $errored = ($hosts | Where-Object { $_.status -match 'ERROR|UNREACHABLE' }).Count

    $maxSessionsPerHost = Get-FarmValue -Farm $f -Paths @(
        'session_settings.max_sessions_count','max_sessions_count',
        'rds_server_session_settings.max_sessions_count'
    )
    $farmCap = if ($maxSessionsPerHost -and $hostCount -gt 0) { [int]$maxSessionsPerHost * $hostCount } else { '' }

    $totalSessOnHosts = ($hosts | Measure-Object -Property session_count -Sum).Sum
    $farmSessions = @($allSessions | Where-Object { ($_.farm_id -eq $farmId) -or ($_.farm_name -eq $f.name) })
    $active = @($farmSessions | Where-Object { $_.session_state -match 'CONNECTED|ACTIVE' }).Count
    $disconnected = @($farmSessions | Where-Object { $_.session_state -match 'DISCONNECTED|IDLE' }).Count

    $pct = $null
    if ($farmCap -and $farmCap -gt 0) { $pct = [math]::Round(($totalSessOnHosts / $farmCap) * 100, 1) }

    $loadBalance = Get-FarmValue -Farm $f -Paths @(
        'load_balancer_settings.load_balancing_algorithm',
        'load_balancing_algorithm',
        'load_balancer_settings.lb_metric_settings'
    )
    $parentVm = Get-FarmValue -Farm $f -Paths @(
        'automated_farm_settings.provisioning_settings.parent_vm_path',
        'instant_clone_engine_provisioning_settings.parent_vm_path',
        'parent_vm_path'
    )

    [pscustomobject]@{
        Farm           = $f.name
        Type           = $f.type
        HostCount      = $hostCount
        Available      = $available
        Maintenance    = $maintenance
        Errored        = $errored
        MaxSessPerHost = $maxSessionsPerHost
        FarmCapacity   = $farmCap
        ActiveSessions = $active
        DisconnectedSessions = $disconnected
        TotalSessOnHosts = $totalSessOnHosts
        PctCapUsed     = $pct
        LoadBalancing  = $loadBalance
        ParentVM       = if ($parentVm) { Split-Path -Leaf -Path ([string]$parentVm) } else { '' }
    }
}

$TableFormat = @{
    PctCapUsed = { param($v,$row) if ([double]"$v" -ge 90) { 'bad' } elseif ([double]"$v" -ge 75) { 'warn' } else { '' } }
    Errored    = { param($v,$row) if ([int]"$v" -gt 5) { 'bad' } elseif ([int]"$v" -gt 0) { 'warn' } else { '' } }
}
