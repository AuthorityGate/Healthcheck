# Start of Settings
# End of Settings

$Title          = 'NSX Logical Switches (legacy MP API)'
$Header         = '[count] logical switch(es) on management API'
$Comments       = 'Migrate from MP API logical-switches to Policy API segments. MP-only objects are deprecation risk.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P3'
$Recommendation = "Migrate via 'Promote MP Objects' wizard."

if (-not (Get-NSXRestSession)) { return }
$ls = Get-NSXLogicalSwitch
if (-not $ls) { return }
[pscustomobject]@{ LogicalSwitchCountMp = if ($ls) { @($ls).Count } else { 0 } }
