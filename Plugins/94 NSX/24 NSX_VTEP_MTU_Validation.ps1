# Start of Settings
# End of Settings

$Title          = 'NSX VTEP MTU Validation'
$Header         = 'Per-host VTEP MTU values (overlay must be >= 1700)'
$Comments       = "Reference: 'Configure Transport Node' (NSX docs). Overlay encap requires MTU 1700+; jumbo frames (9000) preferred."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P1'
$Recommendation = "Set MTU 9000 on all uplink profiles + physical fabric. Test with 'esxcli network ip interface ipv4 get -i vmkN'."

if (-not (Get-NSXRestSession)) { return }
try { $tn = Invoke-NSXRest -Path '/api/v1/transport-nodes' } catch { return }
if (-not $tn) { return }
foreach ($x in $tn) {
    foreach ($hsw in $x.host_switch_spec.host_switches) {
        if (-not $hsw.uplinks) { continue }
        [pscustomobject]@{
            Host          = $x.display_name
            HostSwitch    = $hsw.host_switch_name
            Uplinks       = ($hsw.uplinks | ForEach-Object { $_.uplink_name }) -join ','
        }
    }
}
