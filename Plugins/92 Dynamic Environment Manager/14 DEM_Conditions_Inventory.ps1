# Start of Settings
# End of Settings

$Title          = 'DEM Conditions Inventory'
$Header         = '[count] DEM conditional rule(s)'
$Comments       = 'Conditions (group memberships, OS detection, time of day) gate DEM application. Sprawl = unpredictable behaviour.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P3'
$Recommendation = 'Audit Conditions; consolidate.'

$share = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware UEM\Agent\FlexEngine' -ErrorAction SilentlyContinue).ConfigShare
if (-not $share -or -not (Test-Path $share)) { return }
$cfg = Get-ChildItem -Path (Join-Path $share 'Conditions') -Recurse -ErrorAction SilentlyContinue
[pscustomobject]@{ ConditionConfigs = if ($cfg) { $cfg.Count } else { 0 } }
