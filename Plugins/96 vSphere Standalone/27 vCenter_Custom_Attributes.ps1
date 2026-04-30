# Start of Settings
# End of Settings

$Title          = 'vCenter Custom Attributes'
$Header         = 'Inventory of vCenter custom attributes'
$Comments       = 'Custom attributes (per-VM tags) accumulate over time. Sprawl makes inventory queries slow.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Audit and remove unused custom attributes via Tags & Custom Attributes UI.'

if (-not $Global:VCConnected) { return }
$ca = Get-CustomAttribute -ErrorAction SilentlyContinue
if (-not $ca) { return }
foreach ($a in $ca) {
    [pscustomobject]@{ Name=$a.Name; TargetType=$a.TargetType; Key=$a.Key }
}
