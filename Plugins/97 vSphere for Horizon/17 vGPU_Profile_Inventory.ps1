# Start of Settings
# End of Settings

$Title          = 'NVIDIA vGPU Profile Inventory'
$Header         = '[count] vGPU-attached VM(s) across the cluster'
$Comments       = 'Per-VM NVIDIA vGPU profile assignments + per-host GPU capacity. Common Horizon vGPU patterns: Q-series for engineering CAD, B-series for knowledge workers with light GPU, A-series for VDI shared-graphics. Mixed profiles per host are not supported (best-effort scheduling only).'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '97 vSphere for Horizon'
$Severity       = 'P3'
$Recommendation = 'Confirm host-side vGPU scheduler (best-effort vs equal share vs fixed share) matches workload. Match driver+manager versions across the fleet via host profile or vLCM.'

if (-not $Global:VCConnected) { return }

foreach ($vm in (Get-VM -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $devs = $vm.ExtensionData.Config.Hardware.Device
        $vgpus = @($devs | Where-Object {
            $_.Backing -and $_.Backing.GetType().Name -match 'PciPassthrough.*Backing' -and
            $_.Backing.Vgpu
        })
        foreach ($g in $vgpus) {
            [pscustomobject]@{
                VM       = $vm.Name
                Host     = if ($vm.VMHost) { $vm.VMHost.Name } else { '' }
                Cluster  = if ($vm.VMHost -and $vm.VMHost.Parent) { $vm.VMHost.Parent.Name } else { '' }
                Profile  = $g.Backing.Vgpu
                PowerState = $vm.PowerState
                GuestOS  = if ($vm.Guest) { $vm.Guest.OSFullName } else { '' }
            }
        }
    } catch { }
}
