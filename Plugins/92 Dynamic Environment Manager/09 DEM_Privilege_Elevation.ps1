# Start of Settings
# End of Settings

$Title          = 'DEM Privilege Elevation'
$Header         = '[count] DEM privilege-elevation rules'
$Comments       = 'Privilege elevation grants admin-on-demand for specific apps. Audit count and target apps.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P2'
$Recommendation = 'Tighten conditions (group memberships, time-of-day) on each rule; log elevations to SIEM.'

$share = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware UEM\Agent\FlexEngine' -ErrorAction SilentlyContinue).ConfigShare
if (-not $share -or -not (Test-Path $share)) { return }
$cfg = Get-ChildItem -Path (Join-Path $share 'PrivilegeElevation') -Recurse -ErrorAction SilentlyContinue
[pscustomobject]@{ PrivilegeElevationConfigs = if ($cfg) { $cfg.Count } else { 0 } }
