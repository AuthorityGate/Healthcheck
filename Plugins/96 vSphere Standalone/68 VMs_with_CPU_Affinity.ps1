# Start of Settings
# End of Settings

$Title          = 'VMs with CPU Affinity Pinned'
$Header         = '[count] VM(s) with CPU affinity set'
$Comments       = "CPU affinity pins a VM to specific physical cores - it defeats DRS, prevents vMotion (often only allowed at power-off), and breaks NUMA scheduler logic. Use Reservations / Shares instead. Acceptable only for niche edge cases (latency-sensitive packet-processing VNFs with vendor guidance)."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P2'
$Recommendation = "VM -> Edit Settings -> CPU -> Scheduling Affinity -> clear. Power-off the VM first (pinning often blocks runtime change). Document any vendor-required exceptions."

if (-not $Global:VCConnected) { return }

foreach ($vm in (Get-VM -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $aff = $vm.ExtensionData.Config.CpuAffinity
        if ($aff -and $aff.AffinitySet -and $aff.AffinitySet.Count -gt 0) {
            [pscustomobject]@{
                VM           = $vm.Name
                Cluster      = if ($vm.VMHost -and $vm.VMHost.Parent) { $vm.VMHost.Parent.Name } else { '' }
                AffinitySet  = ($aff.AffinitySet -join ',')
                PowerState   = $vm.PowerState
            }
        }
    } catch { }
}

$TableFormat = @{
    AffinitySet = { param($v,$row) 'warn' }
}
