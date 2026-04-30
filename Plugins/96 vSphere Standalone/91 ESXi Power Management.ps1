# Start of Settings
# End of Settings

$Title          = "ESXi Power Management Policy"
$Header         = "[count] host(s) reporting power policy + current state"
$Comments       = "Per-host power-management policy. Default 'Balanced' policy on ESXi can introduce latency in VDI by parking CPU cores aggressively (KB 1018206). HighPerformance policy keeps cores at full clock - recommended for VDI clusters."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P3"
$Recommendation = "Switch VDI cluster hosts to High Performance via Configure -> Hardware -> Power Management. BIOS-level OS-controlled C/P-state must also be enabled for the OS policy to apply."

if (-not $Global:VCConnected) { return }
$hosts = @(Get-VMHost -ErrorAction SilentlyContinue)
foreach ($h in $hosts) {
    if (-not $h) { continue }
    $pm = $null
    try { $pm = Get-View $h.Id -Property 'Hardware.CpuPowerManagementInfo','Config.PowerSystemInfo','Config.PowerSystemCapability' -ErrorAction Stop } catch { }
    [pscustomobject]@{
        Host          = $h.Name
        Cluster       = if ($h.Parent) { $h.Parent.Name } else { '' }
        PowerPolicy   = if ($pm) { $pm.Config.PowerSystemInfo.CurrentPolicy.ShortName } else { '' }
        PolicyDesc    = if ($pm) { $pm.Config.PowerSystemInfo.CurrentPolicy.Name } else { '' }
        CurrentMhz    = if ($pm) { $pm.Hardware.CpuPowerManagementInfo.CurrentPolicy } else { '' }
        Capability    = if ($pm -and $pm.Config.PowerSystemCapability.AvailablePolicy) { ($pm.Config.PowerSystemCapability.AvailablePolicy.ShortName -join ', ') } else { '' }
    }
}

$TableFormat = @{
    PowerPolicy = { param($v,$row) if ($v -match 'high') { 'ok' } elseif ($v -match 'balanced|custom') { 'warn' } elseif ($v -match 'low') { 'bad' } else { '' } }
}
