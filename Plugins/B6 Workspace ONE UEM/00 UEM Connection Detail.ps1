# Start of Settings
# End of Settings

$Title          = "WS1 UEM Connection Detail"
$Header         = "Workspace ONE UEM (AirWatch) tenant + version + topline counts"
$Comments       = "First plugin in the UEM scope. Confirms Basic auth + tenant API key are valid, dumps tenant version, and pulls a one-row OG / device / app count summary so the operator immediately sees scope."
$Display        = "List"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B6 Workspace ONE UEM"
$Severity       = "Info"
$Recommendation = "If counts return 0 across the board, the API admin account is scoped to a Customer-level OG that has no devices. Re-bind to a higher OG (Global / Customer) for full visibility."

$s = Get-UEMRestSession
if (-not $s) {
    [pscustomobject]@{ Status = '(not connected)'; Note = 'WS1 UEM plugins skip. Set Server / User / Password / API key on the WS1 UEM tab.' }
    return
}

$info = $s.SystemInfo
$ogProbe = Get-UEMOrganizationGroup
$devProbe = Get-UEMDeviceCount

[pscustomobject]@{
    'Tenant FQDN'         = $s.Server
    'Connected At'        = $s.ConnectedAt
    'Console Version'     = if ($info) { $info.ProductVersion } else { '' }
    'Major Version'       = if ($info) { $info.ApiVersion } else { '' }
    'Build Hash'          = if ($info) { $info.BuildNumber } else { '' }
    'Calling Admin'       = $s.Credential.UserName
    'OG Total (visible)'  = if ($ogProbe) { $ogProbe.Total } else { '' }
    'Device Total (visible)' = if ($devProbe) { $devProbe.Total } else { '' }
}
