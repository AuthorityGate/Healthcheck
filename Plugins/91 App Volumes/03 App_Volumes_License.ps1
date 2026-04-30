# Start of Settings
# End of Settings

$Title          = 'App Volumes License'
$Header         = 'Subscription license posture'
$Comments       = 'Verify license entitlement vs deployed managers. Subscription enforces user count.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P2'
$Recommendation = 'Settings -> License -> upload current key. Note expiry; renew 60 days out.'

if (-not (Get-AVRestSession)) { return }
$l = Get-AVLicense
if (-not $l) { return }
[pscustomobject]@{
    Edition         = $l.edition
    LicensedUsers   = $l.licensed_users
    LicensedAgents  = $l.licensed_agents
    Expiration      = $l.expiration_date
    Type            = $l.type
}
