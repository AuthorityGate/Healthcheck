# Start of Settings
# End of Settings

$Title          = 'vCenter Plugin Manager'
$Header         = '[count] vCenter plugin(s) loaded'
$Comments       = 'Stale 3rd-party plugins (legacy vRealize, retired Veeam) clutter the vSphere Client + slow login.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'vCenter -> Administration -> Solutions -> Plug-ins. Remove obsolete entries.'

if (-not $Global:VCConnected) { return }
$mgr = Get-View 'ServiceInstance' -ErrorAction SilentlyContinue
$pmgr = Get-View $mgr.Content.ExtensionManager -ErrorAction SilentlyContinue
if (-not $pmgr) { return }
foreach ($e in $pmgr.ExtensionList) {
    [pscustomobject]@{
        Plugin   = $e.Description.Label
        Key      = $e.Key
        Version  = $e.Version
        Company  = $e.Company
    }
}
