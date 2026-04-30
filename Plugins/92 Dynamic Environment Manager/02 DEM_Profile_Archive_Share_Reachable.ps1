# Start of Settings
# End of Settings

$Title          = 'DEM Profile Archive Share Reachable'
$Header         = 'DEM profile archive path'
$Comments       = 'Profile archive = roaming user data. If unreachable, users get fresh profile on every logon (visible by lost taskbar/IE prefs).'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P1'
$Recommendation = "Verify SMB share path and that 'Authenticated Users' (or DEM 'Users' group) has Modify on subfolders."

$archive = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware UEM\Agent\FlexEngine' -ErrorAction SilentlyContinue).ProfileArchives
if (-not $archive) { return }
[pscustomobject]@{
    ProfileArchives = $archive
    Reachable       = (Test-Path $archive)
}
