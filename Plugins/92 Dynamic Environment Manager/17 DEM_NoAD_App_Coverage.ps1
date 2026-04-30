# Start of Settings
# End of Settings

$Title          = "DEM NoAD vs DEM Standard Coverage"
$Header         = "DEM mode hint and configured share counts"
$Comments       = "Surfaces whether DEM is running NoAD-mode (FlexConfig only, no profile capture) or full-mode (both FlexConfig + Profile). Comes down to: are there profile archives on the share, and does the FlexEngine GPO have the NoAD switch set."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "92 Dynamic Environment Manager"
$Severity       = "Info"
$Recommendation = "If NoAD only, profile captures must come from elsewhere (FSLogix or local profile) - confirm with the customer. If full DEM but no Profile/Archive folder content, profiles are not being captured."

$share = $Global:DEMConfigShare
if (-not $share -or -not (Test-Path $share)) {
    [pscustomobject]@{ Mode='Unknown'; Note='DEMConfigShare not set or unreachable.' }
    return
}
$archive = $Global:DEMArchiveShare
$noADHints = @{
    HasProfileFolder       = (Test-Path (Join-Path $share 'Profiles'))
    HasArchiveShare        = ($archive -and (Test-Path $archive))
    GeneralCount           = if (Test-Path (Join-Path $share 'General')) { @(Get-ChildItem (Join-Path $share 'General') -Recurse -Filter *.xml -ErrorAction SilentlyContinue).Count } else { 0 }
    PrivElevationCount     = if (Test-Path (Join-Path $share 'PrivilegeElevation')) { @(Get-ChildItem (Join-Path $share 'PrivilegeElevation') -Recurse -Filter *.xml -ErrorAction SilentlyContinue).Count } else { 0 }
    AppBlockerCount        = if (Test-Path (Join-Path $share 'ApplicationBlocker')) { @(Get-ChildItem (Join-Path $share 'ApplicationBlocker') -Recurse -Filter *.xml -ErrorAction SilentlyContinue).Count } else { 0 }
}

$mode = if ($noADHints.HasProfileFolder -or $noADHints.HasArchiveShare) { 'Full (NoAD off)' } else { 'NoAD (FlexConfig only)' }
[pscustomobject]@{
    Mode               = $mode
    HasProfileFolder   = $noADHints.HasProfileFolder
    HasArchiveShare    = $noADHints.HasArchiveShare
    GeneralCount       = $noADHints.GeneralCount
    PrivElevationCount = $noADHints.PrivElevationCount
    AppBlockerCount    = $noADHints.AppBlockerCount
}
