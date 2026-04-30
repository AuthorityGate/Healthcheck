# Start of Settings
$MaxRendered = 500
# End of Settings

$Title          = "UEM MDM Profile Inventory"
$Header         = "[count] MDM profile(s) deployed"
$Comments       = "Per-platform MDM profile inventory: passcode policy, Wi-Fi, VPN, restrictions, certificate, e-mail. Profile assignment + status (Active / Inactive) gives you the change-control surface area."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B6 Workspace ONE UEM"
$Severity       = "Info"
$Recommendation = "Profiles flagged Inactive that still have device assignments leave devices in a configuration limbo - either re-activate or remove the assignment. Profile-versions stuck at v1 with thousands of devices warrant testing before bumping."

if (-not (Get-UEMRestSession)) { return }
$resp = Get-UEMProfile
if (-not $resp -or -not $resp.Profiles) {
    [pscustomobject]@{ Note = 'No MDM profiles returned.' }
    return
}

$rendered = 0
foreach ($p in $resp.Profiles) {
    if ($rendered -ge $MaxRendered) { break }
    [pscustomobject]@{
        Name             = $p.ProfileName
        Platform         = $p.Platform
        Status           = $p.Status
        OrganizationGroup = if ($p.LocationGroupName) { $p.LocationGroupName } else { '' }
        AssignmentType   = $p.AssignmentType
        DeviceCount      = $p.AssignedDeviceCount
        ProfileVersion   = $p.ProfileVersion
        Description      = if ($p.Description) { $p.Description.Substring(0,[Math]::Min(80,$p.Description.Length)) } else { '' }
    }
    $rendered++
}

$TableFormat = @{
    Status = { param($v,$row) if ($v -eq 'Active') { 'ok' } elseif ($v -eq 'Inactive') { 'warn' } else { '' } }
}
