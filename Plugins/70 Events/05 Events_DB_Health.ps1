# Start of Settings
# End of Settings

$Title          = 'Horizon Events DB Health'
$Header         = "Events DB connection + recent activity"
$Comments       = "Probes the Horizon Events DB for connection state + most-recent event timestamp. Stale events (no activity > 1h) suggests CS-to-DB connection broken. DB size growth indicates retention policy."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '70 Events'
$Severity       = 'P2'
$Recommendation = "If MostRecentEvent > 1h ago: CS not writing events. Verify SQL connectivity, service account, AlwaysOn AG listener (if used). Audit-trail gap during the silent period."

if (-not (Get-HVRestSession)) { return }

try { $cfg = Invoke-HVRest -Path '/v1/config/event-database' -NoPaging } catch { return }
if (-not $cfg) { return }

$row = [pscustomobject]@{
    DatabaseType    = $cfg.database_type
    Server          = $cfg.server_name
    Port            = $cfg.server_port
    DatabaseName    = $cfg.database_name
    User            = $cfg.user_name
    UseSSL          = $cfg.use_ssl
    Status          = if ($cfg.is_event_database_configured) { 'Configured' } else { 'Not configured' }
    Note            = ''
}
$row

# Fetch most recent event - tells us write-side is alive
try {
    $recentEvents = Invoke-HVRest -Path '/v1/external/events?size=1' -NoPaging
    if ($recentEvents -and $recentEvents.Count -gt 0) {
        $e = $recentEvents[0]
        $ts = if ($e.time) { (Get-Date '1970-01-01').AddMilliseconds([int64]$e.time) } else { $null }
        $age = if ($ts) { [int]((Get-Date) - $ts).TotalMinutes } else { $null }

        [pscustomobject]@{
            DatabaseType    = '(activity probe)'
            Server          = ''
            Port            = ''
            DatabaseName    = ''
            User            = ''
            UseSSL          = ''
            Status          = 'MostRecentEvent'
            Note            = "Last event $age min ago: $($e.module) - $($e.severity)"
        }
    }
} catch { }
