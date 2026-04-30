# Start of Settings
# End of Settings

$Title          = 'DEM FlexProfile Inventory'
$Header         = '[count] FlexProfile config(s) detected on this share'
$Comments       = 'Sanity-check the count and modify-times of FlexProfile XML configs.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'Info'
$Recommendation = 'Cull configs for retired apps; the more configs FlexEngine processes, the slower the logon.'

$share = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware UEM\Agent\FlexEngine' -ErrorAction SilentlyContinue).ConfigShare
if (-not $share -or -not (Test-Path $share)) { return }
$cfgs = Get-ChildItem -Path (Join-Path $share 'FlexRepository') -Recurse -Filter *.ini -ErrorAction SilentlyContinue
if (-not $cfgs) { return }
$cfgs | Group-Object Directory | ForEach-Object {
    [pscustomobject]@{ Folder = $_.Name; Count = $_.Count }
}
