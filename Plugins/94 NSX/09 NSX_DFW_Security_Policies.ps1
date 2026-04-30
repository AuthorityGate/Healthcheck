# Start of Settings
# End of Settings

$Title          = 'NSX DFW Security Policies'
$Header         = '[count] DFW security polic(ies)'
$Comments       = "Reference: 'Distributed Firewall' (NSX docs). Mass count of policies impacts performance."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P3'
$Recommendation = 'Consolidate duplicate / overlapping policies. Use Service Insertion for IDS/IPS.'

if (-not (Get-NSXRestSession)) { return }
$p = Get-NSXDfwPolicy
if (-not $p) { return }
foreach ($x in $p) {
    [pscustomobject]@{
        Name      = $x.display_name
        Category  = $x.category
        Stateful  = $x.stateful
        Locked    = $x.locked
        RuleCount = if ($x.rule_count) { $x.rule_count } else { 0 }
    }
}
