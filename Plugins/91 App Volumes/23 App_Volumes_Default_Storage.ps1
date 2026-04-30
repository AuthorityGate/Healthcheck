# Start of Settings
# End of Settings

$Title          = 'App Volumes Default Storage'
$Header         = 'Default storage / replica destination configured'
$Comments       = 'AV needs a default destination for new packages + writables. Without it, provisioning hangs.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P2'
$Recommendation = "Settings -> Defaults -> set 'Storage for Writables / AppStacks' to a healthy datastore."

if (-not (Get-AVRestSession)) { return }
try { $s = Invoke-AVRest -Path '/cv_api/setting' } catch { return }
if (-not $s) { return }
[pscustomobject]@{
    DefaultDatastore = $s.default_datastore
    DefaultPath      = $s.default_path
    DefaultTemplate  = $s.default_template
}
