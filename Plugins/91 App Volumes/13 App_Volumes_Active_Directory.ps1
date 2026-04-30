# Start of Settings
# End of Settings

$Title          = 'App Volumes Active Directory'
$Header         = 'AD binding inventory'
$Comments       = "Reference: 'Active Directory Configuration' (AV docs). AV requires LDAP / LDAPS bind to enumerate user/group SIDs."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P1'
$Recommendation = "Verify bind account, base DN, LDAPS cert chain. Test 'Sync now' from AV console."

if (-not (Get-AVRestSession)) { return }
$ad = Get-AVAdConfig
if (-not $ad) { return }
foreach ($d in $ad.active_directories) {
    [pscustomobject]@{
        Name      = $d.name
        Domain    = $d.domain
        BindUser  = $d.username
        Ldaps     = $d.use_ssl
        Status    = $d.status
        LastSync  = $d.last_sync_time
    }
}
