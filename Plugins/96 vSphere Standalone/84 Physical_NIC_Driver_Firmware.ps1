# Start of Settings
# End of Settings

$Title          = 'Physical NIC Driver / Firmware Drift'
$Header         = '[count] driver/firmware drift row(s) across hosts'
$Comments       = 'Per-host pNIC inventory with driver + firmware versions. Drift across hosts in the same cluster is a common cause of intermittent vMotion / vSAN packet loss. VMware HCL keys off this combination.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Update to the HCL-listed driver+firmware combo for your NIC + ESXi version. Apply via vLCM image to enforce uniformity.'

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $esxcli = Get-EsxCli -V2 -VMHost $h -ErrorAction Stop
        $nics = $esxcli.network.nic.list.Invoke()
        foreach ($n in $nics) {
            try {
                $info = $esxcli.network.nic.get.Invoke(@{ nicname = $n.Name })
                [pscustomobject]@{
                    Host        = $h.Name
                    NIC         = $n.Name
                    Driver      = $info.DriverInfo.Driver
                    DriverVer   = $info.DriverInfo.Version
                    Firmware    = $info.DriverInfo.FirmwareVersion
                    LinkStatus  = $n.LinkStatus
                    Speed       = $n.Speed
                    Duplex      = $n.Duplex
                    PciDevice   = $info.PCIDeviceID
                }
            } catch { }
        }
    } catch { }
}
