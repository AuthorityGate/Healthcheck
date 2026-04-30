# Start of Settings
# End of Settings

$Title          = "NIC Teaming Uniformity"
$Header         = "[count] vSwitch(es) with single uplink or no failover"
$Comments       = "VMware KB 1004088 / vSphere Networking Guide: every vSwitch carrying production traffic should have at least 2 active or active+standby uplinks for redundancy. Single-uplink switches will black-hole traffic on a single physical NIC failure."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "Add a second uplink and set Failover Order to 'Active/Active' or 'Active/Standby'. Verify both uplinks land on different physical switches (or different chassis line cards)."

if (-not $Global:VCConnected) { return }

Get-VirtualSwitch -Standard -ErrorAction SilentlyContinue | ForEach-Object {
    $uplinks = @($_.Nic)
    if ($uplinks.Count -lt 2) {
        [pscustomobject]@{
            Type     = 'Standard'
            Switch   = $_.Name
            Host     = $_.VMHost.Name
            Uplinks  = ($uplinks -join ', ')
            Count    = $uplinks.Count
        }
    }
}
Get-VDSwitch -ErrorAction SilentlyContinue | ForEach-Object {
    $vds = $_
    foreach ($vmh in (Get-VMHost -DistributedSwitch $vds -ErrorAction SilentlyContinue)) {
        $pnics = (Get-VMHostNetworkAdapter -VMHost $vmh -DistributedSwitch $vds -Physical -ErrorAction SilentlyContinue) | ForEach-Object { $_.Name }
        if ($pnics.Count -lt 2) {
            [pscustomobject]@{
                Type    = 'Distributed'
                Switch  = $vds.Name
                Host    = $vmh.Name
                Uplinks = ($pnics -join ', ')
                Count   = $pnics.Count
            }
        }
    }
}

$TableFormat = @{ Count = { param($v,$row) if ([int]$v -lt 2) { 'bad' } else { '' } } }
