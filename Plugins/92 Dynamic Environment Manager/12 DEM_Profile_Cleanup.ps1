# Start of Settings
# End of Settings

$Title          = 'DEM Profile Cleanup'
$Header         = 'DEM profile-archive size growth indicator'
$Comments       = 'Roaming profiles tend to grow unboundedly without cleanup tasks. Audit archive size.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P3'
$Recommendation = "Use FlexEngine -refresh archive cleanup task on logoff. Apply 'Clean profiles' policy."

$archive = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware UEM\Agent\FlexEngine' -ErrorAction SilentlyContinue).ProfileArchives
if (-not $archive -or -not (Test-Path $archive)) { return }
$size = (Get-ChildItem -Path $archive -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
[pscustomobject]@{ ProfileArchiveBytes = $size; ProfileArchiveGB = [math]::Round($size/1GB, 2) }
