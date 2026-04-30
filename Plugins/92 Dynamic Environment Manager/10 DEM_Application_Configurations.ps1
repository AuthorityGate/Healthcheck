# Start of Settings
# End of Settings

$Title          = 'DEM Application Configurations'
$Header         = 'Application config inventory'
$Comments       = 'Per-app DEM configs. Many shops accumulate configs for retired apps.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P3'
$Recommendation = 'Annual audit; remove configs for retired apps.'

$share = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware UEM\Agent\FlexEngine' -ErrorAction SilentlyContinue).ConfigShare
if (-not $share -or -not (Test-Path $share)) { return }
$apps = Get-ChildItem -Path (Join-Path $share 'General' 'Applications') -Recurse -ErrorAction SilentlyContinue
[pscustomobject]@{ AppConfigCount = if ($apps) { $apps.Count } else { 0 } }
