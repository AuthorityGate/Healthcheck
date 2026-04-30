# Start of Settings
# End of Settings

$Title          = 'Host BIOS Power Profile'
$Header         = '[count] host(s) reporting non-OS-controlled BIOS power profile'
$Comments       = "Reference: KB 1018196. BIOS power profile must be 'OS Controlled' for ESXi power management to do its job."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P3'
$Recommendation = "On Dell: 'Performance Per Watt (DAPC)' for OS control. HPE: 'OS Control Mode'. Lenovo: 'OS Controlled'."

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $hw = $_.ExtensionData.Hardware.CpuPowerManagementInfo
    if ($hw -and $hw.HardwareSupport -and $hw.HardwareSupport -ne 'OS Control') {
        [pscustomobject]@{ Host=$_.Name; HardwareSupport=$hw.HardwareSupport; CurrentPolicy=$hw.CurrentPolicy }
    }
}
