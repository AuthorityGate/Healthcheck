# Start of Settings
$MaxRendered = 500
# End of Settings

$Title          = "UEM Managed Application Inventory"
$Header         = "[count] managed application(s)"
$Comments       = "Every app the tenant pushes to enrolled devices: internal-developed apps, public-store apps, purchased / VPP apps. Per-app: assignment count, install status, latest version. Helps spot stale (no update in 12+ months) apps that should be retired or replaced."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B6 Workspace ONE UEM"
$Severity       = "Info"
$Recommendation = "Apps with high failure rates point at signing-cert / entitlement / push-token issues. VPP apps with an expired token will silently stop installing on new enrollments."

if (-not (Get-UEMRestSession)) { return }
$rendered = 0
$emit = {
    param($AppList, $Source)
    foreach ($a in $AppList) {
        if ($rendered -ge $MaxRendered) { return }
        [pscustomobject]@{
            Name           = $a.ApplicationName
            Source         = $Source
            Platform       = $a.Platform
            Status         = $a.Status
            Version        = $a.AppVersion
            Assignments    = $a.AssignmentCount
            InstallStatus  = $a.InstalledStatus
            LatestPushDate = $a.LastReleasedDate
        }
        $rendered++
    }
}

$internal = Get-UEMInternalApplication
if ($internal -and $internal.Application) { & $emit $internal.Application 'Internal' }
$public = Get-UEMPublicApplication
if ($public -and $public.Application) { & $emit $public.Application 'Public' }
$purchased = Get-UEMPurchasedApplication
if ($purchased -and $purchased.Application) { & $emit $purchased.Application 'Purchased' }

if ($rendered -eq 0) {
    [pscustomobject]@{ Note = 'No managed apps returned (or admin lacks Read access on /api/mam/apps).' }
}
