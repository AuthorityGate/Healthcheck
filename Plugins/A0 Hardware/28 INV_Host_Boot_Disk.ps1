# Start of Settings
# End of Settings

$Title          = 'Host Boot Disk'
$Header         = 'Per-host boot device location + type'
$Comments       = 'ESXi boot location: USB / SD / SATADOM / SSD / NVMe. USB+SD ESXi installs are deprecated since 7.0 U2 and have wear-out concerns.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'P3'
$Recommendation = "Migrate USB/SD boot media to BOSS / SSD / NVMe per VMware KB 85685 ('Deprecation of SD card / USB boot device support')."

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    $boot = $h.ExtensionData.Config.SystemFile | Select-Object -First 1
    $cfg = (Get-AdvancedSetting -Entity $h -Name 'BootDevice.Path' -ErrorAction SilentlyContinue).Value
    [pscustomobject]@{
        Host         = $h.Name
        BootBank     = $boot
        BootDevice   = $cfg
        Note         = if ($cfg -match 'usb|mpx') { 'USB/SD - deprecated' } else { 'OK' }
    }
}
