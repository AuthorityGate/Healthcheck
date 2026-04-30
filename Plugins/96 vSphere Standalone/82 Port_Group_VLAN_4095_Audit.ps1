# Start of Settings
# End of Settings

$Title          = 'Port Groups Using VLAN 4095 (Trunk)'
$Header         = '[count] port group(s) configured for VLAN trunking (4095)'
$Comments       = "VLAN 4095 = trunk all VLANs to the guest (Virtual Guest Tagging). Legitimate for nested ESXi labs, NSX edges, packet-capture VMs, vCenter-recovery. Anywhere else, VST trunks are an over-permissive default that exposes the guest to all VLANs on the uplink."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'For each trunk-mode port group: confirm specific VLANs the guest needs and replace VLAN 4095 with a private VLAN trunk OR a list of allowed VLANs (vDS only). Tag any legitimate trunk PGs in their description.'

if (-not $Global:VCConnected) { return }

# Distributed port groups
foreach ($pg in (Get-VDPortgroup -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $vlan = $pg.VlanConfiguration
        $vlanStr = if ($vlan) { $vlan.ToString() } else { '' }
        if ($vlanStr -match '4095' -or $vlanStr -match 'Trunk') {
            [pscustomobject]@{
                Type      = 'vDS PG'
                PortGroup = $pg.Name
                vDS       = if ($pg.VDSwitch) { $pg.VDSwitch.Name } else { '' }
                VLAN      = $vlanStr
            }
        }
    } catch { }
}
# Standard port groups (rare to have 4095 there - vSS doesn't support trunk lists)
foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue)) {
    foreach ($pg in (Get-VirtualPortGroup -VMHost $h -Standard -ErrorAction SilentlyContinue)) {
        if ($pg.VLanId -eq 4095) {
            [pscustomobject]@{
                Type      = 'vSS PG'
                PortGroup = "$($h.Name)/$($pg.Name)"
                vDS       = ''
                VLAN      = '4095 (trunk)'
            }
        }
    }
}
