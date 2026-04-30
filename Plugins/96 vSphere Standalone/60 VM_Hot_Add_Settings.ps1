# Start of Settings
# End of Settings

$Title          = 'VM Hot-Add CPU/Memory Settings'
$Header         = "[count] VM(s) without hot-add enabled (resize requires power-off)"
$Comments       = "Hot-add CPU + Memory lets you add resources without power-off. For Horizon parents and infrastructure servers, hot-add SHOULD be on. For desktops, off is fine (parents handle resize). Off everywhere = unnecessary maintenance windows."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = "Server-class VMs: enable hot-add CPU + memory. Hot-add memory has light overhead (3-5% CPU); hot-add CPU has slightly higher. For most server workloads = worth it."
if (-not $Global:VCConnected) { return }

foreach ($vm in (Get-VM -ErrorAction SilentlyContinue)) {
    $cfg = $vm.ExtensionData.Config
    $cpuHotAdd = $cfg.CpuHotAddEnabled
    $memHotAdd = $cfg.MemoryHotAddEnabled
    $isServer = $vm.Guest.OSFullName -match 'Server'
    if ($isServer -and (-not $cpuHotAdd -or -not $memHotAdd)) {
        [pscustomobject]@{
            VM       = $vm.Name
            Cluster  = if ($vm.VMHost -and $vm.VMHost.Parent) { $vm.VMHost.Parent.Name } else { '' }
            GuestOS  = $vm.Guest.OSFullName
            CpuHotAdd= $cpuHotAdd
            MemHotAdd= $memHotAdd
            Note     = if (-not $cpuHotAdd -and -not $memHotAdd) { 'Both off' } elseif (-not $cpuHotAdd) { 'CPU hot-add off' } else { 'Memory hot-add off' }
        }
    }
}
