# Start of Settings
# End of Settings

$Title          = "DEM Profile Archive Sizes"
$Header         = "[count] user profile archive(s) sized on the DEM Archive share"
$Comments       = "If a Profile/Archive share is configured, this plugin walks one level deep to size each user's compressed profile (the .ZIP archives). Used to spot fat profiles, abandoned profiles, and storage-growth trends."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "92 Dynamic Environment Manager"
$Severity       = "Info"
$Recommendation = "Profiles >100 MB usually indicate folder-redirection misconfig (Documents not redirected; large .pst files in profile). Audit largest accounts and confirm folder redirection GPOs apply."

$archive = $Global:DEMArchiveShare
if (-not $archive -or -not (Test-Path $archive)) {
    [pscustomobject]@{ Note='DEMArchiveShare not set or unreachable.' }
    return
}

$users = @(Get-ChildItem -Path $archive -Directory -ErrorAction SilentlyContinue)
if ($users.Count -eq 0) {
    [pscustomobject]@{ Note='No user folders found under archive share.' }
    return
}
foreach ($u in $users) {
    $sz = 0; $fileCount = 0; $newest = $null
    try {
        $items = @(Get-ChildItem -Path $u.FullName -Recurse -File -ErrorAction SilentlyContinue)
        $sz = ($items | Measure-Object Length -Sum).Sum
        $fileCount = $items.Count
        $newest = ($items | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    } catch { }
    [pscustomobject]@{
        User           = $u.Name
        SizeMB         = [math]::Round($sz / 1MB, 1)
        FileCount      = $fileCount
        LastModified   = if ($newest) { $newest.ToString('yyyy-MM-dd HH:mm') } else { '' }
        AbandonedDays  = if ($newest) { [int]((Get-Date) - $newest).TotalDays } else { '' }
    }
}

$TableFormat = @{
    SizeMB        = { param($v,$row) if ([double]"$v" -gt 500) { 'bad' } elseif ([double]"$v" -gt 100) { 'warn' } else { '' } }
    AbandonedDays = { param($v,$row) if ([int]"$v" -gt 365) { 'warn' } else { '' } }
}
