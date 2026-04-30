# Start of Settings
# End of Settings

$Title          = 'DEM Self-Support Tools'
$Header         = '[count] DEM self-support config(s)'
$Comments       = 'DEM self-support lets users restore prior profile versions. Unconfigured = helpdesk burden.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P3'
$Recommendation = "Configure 'Self-Support' in DEM Console; expose via tray icon."

$share = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware UEM\Agent\FlexEngine' -ErrorAction SilentlyContinue).ConfigShare
if (-not $share -or -not (Test-Path $share)) { return }
$cfg = Get-ChildItem -Path (Join-Path $share 'SelfSupport') -Recurse -ErrorAction SilentlyContinue
[pscustomobject]@{ SelfSupportConfigs = if ($cfg) { $cfg.Count } else { 0 } }
