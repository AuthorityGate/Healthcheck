# Start of Settings
$MaxRendered = 500
# End of Settings

$Title          = "UEM Smart Group Inventory"
$Header         = "[count] smart group(s) defined"
$Comments       = "Smart Groups are dynamic device collections (filtered by ownership, model, OS, OG, custom attribute). Profiles, apps, and policies all assign to Smart Groups. Hundreds of Smart Groups with overlapping memberships = config sprawl that complicates change-control."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B6 Workspace ONE UEM"
$Severity       = "Info"
$Recommendation = "Smart Groups with 0 devices are candidates for removal. Smart Groups whose member count fluctuates wildly should be audited - the filter criteria may be too narrow / fragile."

if (-not (Get-UEMRestSession)) { return }
$resp = Get-UEMSmartGroup
if (-not $resp -or -not $resp.SmartGroups) {
    [pscustomobject]@{ Note = 'No smart groups returned.' }
    return
}

$rendered = 0
foreach ($g in $resp.SmartGroups) {
    if ($rendered -ge $MaxRendered) { break }
    [pscustomobject]@{
        Name            = $g.Name
        OG              = $g.ManagedByOrganizationGroupName
        DeviceCount     = $g.DeviceCount
        UserCount       = $g.UserCount
        Type            = $g.SmartGroupType
        ProfileCount    = $g.ProfileCount
        AppCount        = $g.ApplicationCount
        Description     = if ($g.Description) { $g.Description.Substring(0,[Math]::Min(80,$g.Description.Length)) } else { '' }
    }
    $rendered++
}
