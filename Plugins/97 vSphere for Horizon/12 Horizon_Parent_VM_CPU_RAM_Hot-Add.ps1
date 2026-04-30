# Start of Settings
# End of Settings

$Title          = 'Horizon Parent VM CPU/RAM Hot-Add'
$Header         = '[count] parent VM(s) with CPU or memory hot-add enabled'
$Comments       = "Reference: 'Horizon Best Practices'. Hot-add forces 100% memory reservation, breaking VDI consolidation ratios."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '97 vSphere for Horizon'
$Severity       = 'P2'
$Recommendation = 'Power off the parent, disable hot-add (CPU + memory), retake snapshot, push image.'

if (-not $Global:VCConnected) { return }
$parents = New-Object System.Collections.Generic.HashSet[string]
if (Get-HVRestSession) {
    foreach ($p in (Get-HVDesktopPool)) {
        foreach ($prop in 'provisioning_settings','instant_clone_engine_provisioning_settings') {
            $s = $p.$prop
            if ($s -and $s.parent_vm_path) { [void]$parents.Add(($s.parent_vm_path -split '/')[-1]) }
        }
    }
}
if (Test-Path Variable:Global:HVManualGoldImageList) {
    foreach ($n in @($Global:HVManualGoldImageList)) { if ($n) { [void]$parents.Add($n) } }
}
if ($parents.Count -eq 0) { return }
foreach ($n in $parents) {
    $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
    if (-not $vm) { continue }
    $cpuHot = $vm.ExtensionData.Config.CpuHotAddEnabled
    $memHot = $vm.ExtensionData.Config.MemoryHotAddEnabled
    if ($cpuHot -or $memHot) {
        [pscustomobject]@{ ParentVM=$vm.Name; CpuHotAdd=$cpuHot; MemHotAdd=$memHot }
    }
}
