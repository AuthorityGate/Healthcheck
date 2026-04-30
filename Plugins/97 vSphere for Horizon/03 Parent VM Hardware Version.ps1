# Start of Settings
# Minimum acceptable VM hardware version for Horizon parent / golden VMs.
# Horizon 8 (2306+) requires vmx-15 or later for full feature set; vTPM (Win11) requires vmx-14 + UEFI.
$MinHardwareVersion = 15
# End of Settings

$Title          = "Horizon Parent VM Hardware Version"
$Header         = "[count] parent VM(s) below hardware version $MinHardwareVersion"
$Comments       = "Per Horizon documentation: parent VMs / golden images for instant-clone or linked-clone pools should run at the highest hardware version supported by every host in the target cluster (commonly vmx-15+). Older HW versions miss VMXNET3 RSSv2, vTPM, secure boot."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P2"
$Recommendation = "Power off parent VM -> Compatibility -> Upgrade VM Compatibility -> select target. Re-take snapshot. Re-publish image to all dependent pools."

if (-not $Global:VCConnected) { return }

# Parent VM set: Horizon REST auto-discovery (when connected) + manual list
# from the 'Pick Gold Images...' picker. Either source alone is valid.
$parents = New-Object System.Collections.Generic.HashSet[string]
if (Get-HVRestSession) {
    foreach ($p in (Get-HVDesktopPool)) {
        foreach ($prop in 'provisioning_settings','instant_clone_engine_provisioning_settings') {
            $s = $p.$prop
            if ($s -and $s.parent_vm_path) {
                [void]$parents.Add(($s.parent_vm_path -split '/')[-1])
            }
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
    $hv = [int]($vm.HardwareVersion -replace '[^0-9]','')
    if ($hv -lt $MinHardwareVersion) {
        [pscustomobject]@{
            ParentVM        = $vm.Name
            HardwareVersion = $vm.HardwareVersion
            GuestOS         = $vm.Guest.OSFullName
            Cluster         = $vm.VMHost.Parent.Name
            Min             = "vmx-$MinHardwareVersion"
        }
    }
}

$TableFormat = @{
    HardwareVersion = { param($v,$row) 'warn' }
}
