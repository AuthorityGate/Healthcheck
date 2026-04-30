# Start of Settings
# End of Settings

$Title          = 'vCenter Inventory Summary'
$Header         = 'vCenter version + build + edition + DB'
$Comments       = 'Top-level vCenter identity: name, version, build, edition, OS type (Windows / Linux), instance UUID, install date.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'Info'
$Recommendation = 'Snapshot vCenter version monthly.'

if (-not $Global:VCConnected) { return }
$vc = $global:DefaultVIServer
if (-not $vc) { return }
$si = Get-View ServiceInstance
$about = $si.Content.About
[pscustomobject]@{
    Name        = $vc.Name
    Version     = $vc.Version
    Build       = $vc.Build
    FullName    = $about.FullName
    OsType      = $about.OsType
    ApiVersion  = $about.ApiVersion
    InstanceUuid = $about.InstanceUuid
    LicenseProductVersion = $about.LicenseProductVersion
    LicenseProductName    = $about.LicenseProductName
    LocaleVersion = $about.LocaleVersion
    User        = $vc.User
}
