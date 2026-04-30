# Start of Settings
# End of Settings

$Title          = "ESXi Host Power Policy"
$Header         = "[count] host(s) not on 'High Performance' power policy"
$Comments       = "VMware KB 1018196: VDI workloads benefit from 'High Performance' over 'Balanced'. The default 'Balanced' caps CPU C-states which adds login-storm jitter."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "95 vSphere Backing Infra"
$Severity       = "P3"
$Recommendation = "Hosts -> Configure -> Hardware -> Power Management -> 'Edit Power Policy' -> 'High Performance'. Apply via host profile to avoid drift."

if (-not $Global:VCConnected) { return }

Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $pol = $_.ExtensionData.Hardware.CpuPowerManagementInfo.CurrentPolicy
    if ($pol -and $pol -ne 'Static' -and $pol -ne 'High Performance') {
        [pscustomobject]@{
            Host    = $_.Name
            Policy  = $pol
            HwInfo  = $_.ExtensionData.Hardware.CpuPowerManagementInfo.HardwareSupport
            Cluster = $_.Parent.Name
        }
    }
}

$TableFormat = @{
    Policy = { param($v,$row) 'warn' }
}
