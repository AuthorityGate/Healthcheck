# Start of Settings
# End of Settings

$Title          = "Veeam B&R Connection Detail"
$Header         = "Veeam Backup & Replication tenant info"
$Comments       = "First plugin in the Backup/DR scope. Validates the Veeam REST API session via /api/v1/serverInfo and dumps version + build."
$Display        = "List"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B7 Backup and DR"
$Severity       = "Info"
$Recommendation = "If 'Server Version' is empty, the OAuth token grant succeeded but the calling user lacks Backup Admin role. Re-bind."

$s = Get-VeeamRestSession
if (-not $s) {
    [pscustomobject]@{ Status = '(not connected)'; Note = 'Veeam plugins skip. Set Veeam Server FQDN / Username / Password / Port (default 9419) on the Veeam tab.' }
    return
}
$info = Get-VeeamServerInfo
$lic  = Get-VeeamLicense
[pscustomobject]@{
    'VBR FQDN'        = $s.Server
    'Connected At'    = $s.ConnectedAt
    'Server Version'  = if ($info) { $info.vbrVersion } else { '' }
    'Build Version'   = if ($info) { $info.patchLevel } else { '' }
    'License Expiry'  = if ($lic) { $lic.expirationDate } else { '' }
    'License Edition' = if ($lic) { $lic.edition } else { '' }
}
