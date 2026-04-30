# Start of Settings
# End of Settings

$Title          = 'App Volumes Application Inventory'
$Header         = "[count] App Volumes 'app product(s)'"
$Comments       = 'Top-level applications grouping packages and markers.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'Info'
$Recommendation = 'Keep app_products clean; archive products replaced by Microsoft 365 in-place app delivery.'

if (-not (Get-AVRestSession)) { return }
$a = Get-AVAppVolume
if (-not $a) { return }
foreach ($p in $a.app_products) {
    [pscustomobject]@{
        Name      = $p.name
        Vendor    = $p.vendor
        Version   = $p.version
        Lifecycle = $p.lifecycle_stage
    }
}
