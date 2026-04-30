# Start of Settings
# End of Settings

$Title          = 'Horizon Parent VM Secure Boot'
$Header         = '[count] parent VM(s) without Secure Boot enabled (UEFI required)'
$Comments       = "Reference: 'Horizon Win11 Requirements'. Win11 needs UEFI + Secure Boot + vTPM. UEFI w/o Secure Boot is a half-baked config."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '97 vSphere for Horizon'
$Severity       = 'P2'
$Recommendation = "VM -> VM Options -> Boot Options -> Firmware = EFI -> 'Secure Boot' = Enable. Power-cycle."

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
    $fw = $vm.ExtensionData.Config.Firmware
    $sb = $vm.ExtensionData.Config.BootOptions.EfiSecureBootEnabled
    if ($fw -ne 'efi' -or -not $sb) {
        [pscustomobject]@{ ParentVM=$vm.Name; Firmware=$fw; SecureBoot=$sb }
    }
}
