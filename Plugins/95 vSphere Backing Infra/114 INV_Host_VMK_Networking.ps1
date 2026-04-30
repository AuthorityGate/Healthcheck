# Start of Settings
# End of Settings

$Title          = 'Host VMK Networking'
$Header         = 'Per-host VMkernel adapter inventory + traffic types'
$Comments       = 'Every VMkernel NIC: IP, netmask, MTU, traffic types enabled (mgmt, vMotion, vSAN, FT, provisioning). MTU + traffic-type drift causes silent perf issues.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'Info'
$Recommendation = 'vMotion + vSAN VMKs should be MTU 9000 end-to-end (KB 1038828).'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    foreach ($v in (Get-VMHostNetworkAdapter -VMHost $h -VMKernel -ErrorAction SilentlyContinue)) {
        [pscustomobject]@{
            Host        = $h.Name
            Vmk         = $v.Name
            IP          = $v.IP
            SubnetMask  = $v.SubnetMask
            Mtu         = $v.Mtu
            PortGroup   = $v.PortGroupName
            MgmtTraffic = $v.ManagementTrafficEnabled
            vMotion     = $v.VMotionEnabled
            FtLogging   = $v.FaultToleranceLoggingEnabled
            VsanTraffic = $v.VsanTrafficEnabled
        }
    }
}
