# Start of Settings
# Recommended virtual hardware for Horizon parent VMs:
$RecommendedScsi = 'ParaVirtual'   # PVSCSI (KB 1010398)
$RecommendedNic  = 'Vmxnet3'       # VMXNET3 - required for full Horizon feature parity
# End of Settings

$Title          = "Horizon Parent VM SCSI / NIC Types"
$Header         = "[count] parent VM(s) using non-recommended SCSI or NIC adapters"
$Comments       = "VMware KB 1010398 (PVSCSI for high-IOPS) + Horizon docs: parent VMs should use ParaVirtual SCSI and VMXNET3 NICs for performance and feature parity (DSX/Blast Extreme bandwidth, RSSv2)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P3"
$Recommendation = "Power off the parent, replace SCSI controller with PVSCSI, replace NIC with VMXNET3, install drivers (Tools), retake snapshot, push image."

if (-not $Global:VCConnected) { return }

# Parent VM set: Horizon REST auto-discovery (when connected) + manual list
# from the 'Pick Gold Images...' picker. Either source alone is valid.
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
    foreach ($n in @($Global:HVManualGoldImageList)) {
        if ($n) { [void]$parents.Add($n) }
    }
}
if ($parents.Count -eq 0) { return }

foreach ($n in $parents) {
    $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
    if (-not $vm) { continue }
    $scsi = (Get-ScsiController -VM $vm -ErrorAction SilentlyContinue).Type | Sort-Object -Unique
    $nic  = (Get-NetworkAdapter -VM $vm -ErrorAction SilentlyContinue).Type | Sort-Object -Unique
    $bad  = ($scsi -and ($scsi -notcontains $RecommendedScsi)) -or ($nic -and ($nic -notcontains $RecommendedNic))
    if ($bad) {
        [pscustomobject]@{
            ParentVM = $vm.Name
            ScsiType = $scsi -join ', '
            NicType  = $nic  -join ', '
            Recommended = "$RecommendedScsi / $RecommendedNic"
        }
    }
}

$TableFormat = @{
    ScsiType = { param($v,$row) if ($v -notmatch [regex]::Escape($RecommendedScsi)) { 'warn' } else { '' } }
    NicType  = { param($v,$row) if ($v -notmatch [regex]::Escape($RecommendedNic))  { 'warn' } else { '' } }
}
