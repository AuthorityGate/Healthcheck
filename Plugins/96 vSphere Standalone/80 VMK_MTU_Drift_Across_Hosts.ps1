# Start of Settings
# End of Settings

$Title          = 'VMkernel MTU Drift Across Cluster'
$Header         = '[count] VMkernel role(s) with MTU drift across hosts'
$Comments       = "vMotion / vSAN / FT VMK adapters typically run jumbo (9000 MTU). MTU mismatch across hosts in the same cluster causes silent fragmentation/black-holing on the wire. Per-role MTU should be uniform per cluster (and uniform end-to-end on the physical fabric)."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P2'
$Recommendation = 'Pick one MTU per VMK role per cluster. Validate physical switch ports on the same VLAN match. Test with: vmkping -d -s 8972 <peer-VMK-IP> -I vmkN.'

if (-not $Global:VCConnected) { return }

foreach ($c in (Get-Cluster -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $hosts = @($c | Get-VMHost)
    if ($hosts.Count -lt 2) { continue }
    $byRole = @{}
    foreach ($h in $hosts) {
        foreach ($v in (Get-VMHostNetworkAdapter -VMHost $h -VMKernel -ErrorAction SilentlyContinue)) {
            $roles = @()
            if ($v.ManagementTrafficEnabled) { $roles += 'Mgmt' }
            if ($v.VMotionEnabled)           { $roles += 'vMotion' }
            if ($v.FaultToleranceLoggingEnabled) { $roles += 'FT' }
            if ($v.VsanTrafficEnabled)       { $roles += 'vSAN' }
            if ($roles.Count -eq 0)          { $roles += 'Other' }
            foreach ($r in $roles) {
                $key = "$($c.Name) | $r"
                if (-not $byRole.ContainsKey($key)) { $byRole[$key] = @{} }
                if (-not $byRole[$key].ContainsKey($v.Mtu)) { $byRole[$key][$v.Mtu] = @() }
                $byRole[$key][$v.Mtu] += "$($h.Name)/$($v.Name)"
            }
        }
    }
    foreach ($key in $byRole.Keys) {
        $mtus = $byRole[$key]
        if ($mtus.Keys.Count -gt 1) {
            [pscustomobject]@{
                ClusterRole = $key
                Distribution = ($mtus.Keys | Sort-Object | ForEach-Object { "MTU=$_ on [$(@($mtus[$_]) -join ', ')]" }) -join ' || '
                Issue        = "MTU drift across hosts for this VMK role - $($mtus.Keys.Count) different MTUs detected."
            }
        }
    }
}
