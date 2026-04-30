# Start of Settings
# End of Settings

$Title          = 'App Volumes ThinApp Inventory'
$Header         = 'ThinApp packages registered with AV'
$Comments       = "Reference: 'Provisioning ThinApps' (AV docs). ThinApp delivery is a legacy mode; check usage."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P3'
$Recommendation = 'Migrate ThinApp packages to App Volumes app packages over time.'

if (-not (Get-AVRestSession)) { return }
try { $t = Invoke-AVRest -Path '/cv_api/thinapps' } catch { return }
if (-not $t) { return }
[pscustomobject]@{ ThinAppCount = if ($t.thinapps) { @($t.thinapps).Count } else { 0 } }
