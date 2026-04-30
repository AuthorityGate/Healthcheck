# Start of Settings
# End of Settings

$Title          = "Event Database Configuration"
$Header         = "Event DB connectivity for the pod"
$Comments       = "Reference: Horizon Admin Guide -> 'Configuring Event Reporting'. Without an event DB, the audit-events plugins cannot report failed authentications, provisioning errors, or session events. SQL Server / Oracle are supported."
$Display        = "List"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "10 Connection Servers"
$Severity       = "P2"
$Recommendation = "Horizon Console -> Settings -> Event Configuration. Configure DB host, port, name, schema, and a least-privileged DB account (db_owner on the events DB)."

if (-not (Get-HVRestSession)) { return }
try {
    $cfg = Invoke-HVRest -Path '/v1/config/event-database' -NoPaging
} catch { return }
if (-not $cfg) { return }

[pscustomobject]@{
    'DB Type'      = $cfg.database_type
    'Server'       = $cfg.server_name
    'Port'         = $cfg.server_port
    'Database'     = $cfg.database_name
    'Username'     = $cfg.user_name
    'TablePrefix'  = $cfg.table_prefix
    'Configured'   = [bool]$cfg.server_name
    'Connected'    = $cfg.is_event_db_connected
}
