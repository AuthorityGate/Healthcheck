# Start of Settings
# End of Settings

$Title          = 'Horizon Parent VM vTPM (Win11)'
$Header         = '[count] Windows 11 parent VM(s) without vTPM'
$Comments       = "Reference: 'Win11 in Horizon' (KB 88001). Win11 requires a vTPM device for full feature support (BitLocker, Credential Guard)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '97 vSphere for Horizon'
$Severity       = 'P2'
$Recommendation = 'Add a vTPM via VM -> Add Device -> Trusted Platform Module. Requires KMS configured first.'

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
    $os = $vm.Guest.OSFullName
    if ($os -match 'Windows 11|Microsoft Windows 11') {
        $hasTpm = $vm.ExtensionData.Config.Hardware.Device | Where-Object { $_.GetType().Name -eq 'VirtualTPM' }
        if (-not $hasTpm) {
            [pscustomobject]@{ ParentVM=$vm.Name; GuestOS=$os; vTPM=$false }
        }
    }
}
