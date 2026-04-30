# Start of Settings
# End of Settings

$Title          = "Standard / Distributed vSwitch MTU Consistency"
$Header         = "[count] vSwitch(es) with non-default or inconsistent MTU"
$Comments       = "VMware KB 1038828 / 2058486: vMotion, vSAN, NFS, and iSCSI VMkernels need MTU 9000 end-to-end (vSwitch + uplink + physical fabric). MTU mismatches cause silent fragmentation, slow vMotion, and vSAN heartbeat loss."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "Set MTU 9000 on each switch hosting vMotion/vSAN/iSCSI/NFS, on the uplinks, and on the physical fabric. Test end-to-end with 'vmkping -d -s 8972 <peer-vmk>'."

if (-not $Global:VCConnected) { return }

# Standard vSwitches
Get-VirtualSwitch -Standard -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Mtu -ne 1500 -and $_.Mtu -ne 9000) {
        [pscustomobject]@{
            Type    = 'Standard'
            Switch  = $_.Name
            Host    = $_.VMHost.Name
            MTU     = $_.Mtu
            Verdict = 'Non-standard MTU'
        }
    }
}
# Distributed switches
Get-VDSwitch -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Mtu -ne 1500 -and $_.Mtu -ne 9000) {
        [pscustomobject]@{
            Type    = 'Distributed'
            Switch  = $_.Name
            Host    = '(cluster-wide)'
            MTU     = $_.Mtu
            Verdict = 'Non-standard MTU'
        }
    }
}

$TableFormat = @{ MTU = { param($v,$row) 'warn' } }
