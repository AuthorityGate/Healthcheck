# Start of Settings
# End of Settings

$Title          = 'App Volumes Failed Packages'
$Header         = '[count] application package(s) in non-OK state'
$Comments       = "Reference: 'Provisioning Errors' (App Volumes docs). Failed/Provisioning-error packages cannot be assigned and consume capture VM time."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P2'
$Recommendation = 'Re-provision failed packages. Common causes: capture VM mid-snapshot, service-pack mismatch.'

if (-not (Get-AVRestSession)) { return }
$pkgResp = Get-AVAppPackage
if (-not $pkgResp) { return }
foreach ($pkg in $pkgResp.app_packages) {
    if ($pkg.status -and $pkg.status -ne 'enabled' -and $pkg.status -ne 'available') {
        [pscustomobject]@{
            Package = $pkg.name; Status = $pkg.status; Reason = $pkg.error_message; Datastore = $pkg.datastore
        }
    }
}
