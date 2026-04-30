# Start of Settings
# End of Settings

$Title          = 'RDS Farm Logoff / Disconnect Policy'
$Header         = 'Per-farm idle disconnect / logoff timers'
$Comments       = "Default 'Never' on either timer holds RDSH session licenses indefinitely. KB 70327: set finite timers (8h disconnect, 12h logoff)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '40 RDS Farms'
$Severity       = 'P3'
$Recommendation = "Farm -> Edit -> Session Settings: 'Disconnected sessions' = 8h, 'Empty sessions' = 'Logoff after 1 minute'."

if (-not (Get-HVRestSession)) { return }
$farms = Get-HVFarm
if (-not $farms) { return }
foreach ($f in $farms) {
    $ss = $f.session_settings
    if (-not $ss) { continue }
    [pscustomobject]@{
        Farm                       = $f.name
        DisconnectedTimeoutMin     = $ss.disconnected_session_timeout_minutes
        DisconnectedTimeoutPolicy  = $ss.disconnected_session_timeout_policy
        EmptySessionTimeoutMin     = $ss.empty_session_timeout_minutes
        EmptySessionTimeoutPolicy  = $ss.empty_session_timeout_policy
    }
}

