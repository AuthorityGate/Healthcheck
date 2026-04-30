# Start of Settings
$MaxOGs = 200
# End of Settings

$Title          = "UEM Organization Group Hierarchy"
$Header         = "[count] organization group(s)"
$Comments       = "OG hierarchy is the root of UEM's scoping model: enrollment routes, profile inheritance, license entitlement all hang off the OG tree. Audit for orphan OGs (no devices), accidental OG-per-user explosion, and wrong-locale OGs."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B6 Workspace ONE UEM"
$Severity       = "Info"
$Recommendation = "Fewer, deeper OGs are easier to maintain than many shallow ones. Each OG with > 0 devices should have at least one Smart Group covering it."

if (-not (Get-UEMRestSession)) { return }
$resp = Get-UEMOrganizationGroup
if (-not $resp -or -not $resp.OrganizationGroups) {
    [pscustomobject]@{ Note = 'No OGs returned (or admin lacks Read access to system.groups).' }
    return
}

$rendered = 0
foreach ($og in $resp.OrganizationGroups) {
    if ($rendered -ge $MaxOGs) { break }
    [pscustomobject]@{
        Name           = $og.Name
        GroupId        = $og.GroupId
        Type           = $og.LocationGroupType
        ParentName     = if ($og.ParentLocationGroup) { $og.ParentLocationGroup.Name } else { '(root)' }
        Country        = $og.Country
        Locale         = $og.Locale
        Timezone       = $og.Timezone
        DeviceCount    = $og.DeviceCount
        UserCount      = $og.UserCount
    }
    $rendered++
}
