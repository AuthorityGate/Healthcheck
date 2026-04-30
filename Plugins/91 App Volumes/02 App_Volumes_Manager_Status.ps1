# Start of Settings
# End of Settings

$Title          = 'App Volumes Manager Status'
$Header         = 'Manager-cluster status and feature flags'
$Comments       = "Reference: App Volumes Admin Guide - 'Manager Cluster'. Healthy cluster = all members reachable, same version, same DB."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P1'
$Recommendation = "Mismatched version or 'down' member: re-register member, restart 'svmanager_server' service, verify shared SQL."

if (-not (Get-AVRestSession)) { return }
$st = Get-AVServerStatus
if (-not $st) { return }
[pscustomobject]@{
    DbConnected         = $st.database_connected
    LdapConnected       = $st.ldap_connected
    AdminCredentialsSet = $st.admin_credentials_set
    Mode                = $st.mode
    LicenseAccepted     = $st.license_accepted
}
