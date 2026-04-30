# Start of Settings
# End of Settings

$Title          = 'NSX Compute Manager Bindings'
$Header         = 'Compute manager / vCenter integration'
$Comments       = 'NSX integrates with vCenter to enumerate hosts/VMs. Stale bindings break DFW Service Insertion.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P1'
$Recommendation = 'Re-validate vCenter bindings; re-trust expired thumbprints.'

if (-not (Get-NSXRestSession)) { return }
$c = Get-NSXComputeManager
if (-not $c) { return }
foreach ($x in $c) {
    [pscustomobject]@{
        Server     = $x.server
        Origin     = $x.origin_type
        Username   = $x.credential.username
    }
}
