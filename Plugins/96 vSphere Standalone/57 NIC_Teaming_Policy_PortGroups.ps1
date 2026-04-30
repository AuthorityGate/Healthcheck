# Start of Settings
# End of Settings

$Title          = 'NIC Teaming Policy per Portgroup'
$Header         = "[count] portgroup(s) with single-uplink configurations"
$Comments       = "Production portgroups should have multiple uplinks for redundancy. Single-uplink portgroup = single switch failure = isolation. Audit teaming + failover policy."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P2'
$Recommendation = "Configure 2+ active OR active+standby uplinks per portgroup. Splitting active/standby on different physical switches = best."

if (-not $Global:VCConnected) { return }

# vDS portgroups (most important)
foreach ($pg in (Get-VDPortgroup -ErrorAction SilentlyContinue)) {
    try {
        $teamingPolicy = $pg.ExtensionData.Config.DefaultPortConfig.UplinkTeamingPolicy
        if (-not $teamingPolicy) { continue }
        $activeUplinks = $teamingPolicy.UplinkPortOrder.ActiveUplinkPort
        $standbyUplinks = $teamingPolicy.UplinkPortOrder.StandbyUplinkPort
        $activeCount = if ($activeUplinks) { @($activeUplinks).Count } else { 0 }
        $standbyCount = if ($standbyUplinks) { @($standbyUplinks).Count } else { 0 }

        if ($activeCount + $standbyCount -lt 2) {
            [pscustomobject]@{
                Type           = 'vDS'
                Switch         = $pg.VDSwitch.Name
                Portgroup      = $pg.Name
                Active         = $activeCount
                Standby        = $standbyCount
                LoadBalancing  = $teamingPolicy.Policy.Value
                Note           = 'Single uplink = no redundancy.'
            }
        }
    } catch { }
}

# Standard switches
foreach ($vs in (Get-VirtualSwitch -Standard -ErrorAction SilentlyContinue)) {
    foreach ($pg in (Get-VirtualPortGroup -VirtualSwitch $vs -ErrorAction SilentlyContinue)) {
        try {
            $policy = Get-NicTeamingPolicy -VirtualPortGroup $pg -ErrorAction SilentlyContinue
            $activeCount = if ($policy.ActiveNic) { @($policy.ActiveNic).Count } else { 0 }
            $standbyCount = if ($policy.StandbyNic) { @($policy.StandbyNic).Count } else { 0 }
            if ($activeCount + $standbyCount -lt 2) {
                [pscustomobject]@{
                    Type = 'vSS'
                    Switch = $vs.Name
                    Portgroup = $pg.Name
                    Active = $activeCount
                    Standby = $standbyCount
                    LoadBalancing = $policy.LoadBalancingPolicy
                    Note = 'Single uplink = no redundancy.'
                }
            }
        } catch { }
    }
}

$TableFormat = @{
    Note = { param($v,$row) if ($v -match 'no redundancy') { 'bad' } else { '' } }
}
