# Start of Settings
# End of Settings

$Title          = 'Horizon Helpdesk Plug-in'
$Header         = 'Helpdesk plug-in / event-database connection state'
$Comments       = "Reference: 'Horizon Help Desk Tool' (Horizon docs). Help Desk reads the event DB; if the event DB is unreachable, helpdesk shows 'no data' and admins lose troubleshooting visibility."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'P3'
$Recommendation = "Verify event DB connectivity (plugin '14 Event Database Status') and Helpdesk role is granted on a separate role."

if (-not (Get-HVRestSession)) { return }
try { $hd = Invoke-HVRest -Path '/v1/config/help-desk' -NoPaging } catch { return }
if (-not $hd) { return }
[pscustomobject]@{
    Enabled                 = $hd.enabled
    PreLaunchSessionTimeout = $hd.pre_launch_session_timeout
    SessionTimeout          = $hd.session_timeout
    EventDbConnected        = $hd.event_db_connected
}

