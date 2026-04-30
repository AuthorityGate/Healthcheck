# Start of Settings
# End of Settings

$Title          = 'App Volumes App Packages'
$Header         = '[count] application packages provisioned'
$Comments       = 'Inventory of all AV packages with their current package state.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'Info'
$Recommendation = 'Track package count over time. Old un-used packages should be deleted to free datastore.'

if (-not (Get-AVRestSession)) { return }
$pkgResp = Get-AVAppPackage
if (-not $pkgResp) { return }
foreach ($pkg in $pkgResp.app_packages) {
    [pscustomobject]@{
        Name        = $pkg.name
        Status      = $pkg.status
        SizeMB      = [math]::Round($pkg.size_mb, 1)
        PackagedAt  = $pkg.packaged_at
        Datastore   = $pkg.datastore
    }
}
