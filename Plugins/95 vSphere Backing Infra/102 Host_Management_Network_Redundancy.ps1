# Start of Settings
# End of Settings

$Title          = 'Host Management Network Redundancy'
$Header         = '[count] host(s) without redundant management VMK'
$Comments       = 'Reference: KB 1004700. A single management vmk = HA isolation responses on NIC failure.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = 'Add a 2nd vmk on a different vSwitch / uplink, or enable management on additional vNICs.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $mgmt = Get-VMHostNetworkAdapter -VMHost $_ -VMKernel -ErrorAction SilentlyContinue | Where-Object { $_.ManagementTrafficEnabled }
    if (@($mgmt).Count -lt 2) {
        [pscustomobject]@{ Host=$_.Name; MgmtVmkCount=@($mgmt).Count }
    }
}
