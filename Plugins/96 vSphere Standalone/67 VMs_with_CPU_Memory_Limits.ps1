# Start of Settings
# End of Settings

$Title          = 'VMs with CPU or Memory Limits Set'
$Header         = '[count] VM(s) with hard CPU or memory limits'
$Comments       = "CPU/memory **reservations** guarantee minimums (often appropriate). CPU/memory **limits** cap maximums even when the host has spare capacity - this is almost always a misconfiguration; people set limits thinking they protect 'noisy neighbors' but instead create silent under-performance. Real noisy-neighbor protection is shares + reservations."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P2'
$Recommendation = "VM -> Edit Settings -> Resources -> CPU/Memory -> Limit = Unlimited (the default). Use shares + reservations to protect critical workloads instead."

if (-not $Global:VCConnected) { return }

foreach ($vm in (Get-VM -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $rp = $vm.ExtensionData.ResourceConfig
        $cpuLimit = $rp.CpuAllocation.Limit
        $memLimit = $rp.MemoryAllocation.Limit
        if (($cpuLimit -gt 0) -or ($memLimit -gt 0)) {
            [pscustomobject]@{
                VM       = $vm.Name
                Cluster  = if ($vm.VMHost -and $vm.VMHost.Parent) { $vm.VMHost.Parent.Name } else { '' }
                CpuLimitMHz = if ($cpuLimit -gt 0) { $cpuLimit } else { 'unlimited' }
                MemLimitMB  = if ($memLimit -gt 0) { $memLimit } else { 'unlimited' }
                PowerState  = $vm.PowerState
            }
        }
    } catch { }
}

$TableFormat = @{
    CpuLimitMHz = { param($v,$row) if ($v -ne 'unlimited') { 'warn' } else { '' } }
    MemLimitMB  = { param($v,$row) if ($v -ne 'unlimited') { 'warn' } else { '' } }
}
