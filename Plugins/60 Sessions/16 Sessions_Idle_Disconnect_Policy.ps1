# Start of Settings
# End of Settings

$Title          = 'Pool Session Idle / Disconnect Policy'
$Header         = "[count] pool(s) with idle/disconnect policy configured"
$Comments       = "Idle timeout + disconnect policy controls when sessions reclaim capacity. No timeout = users walk away, sessions linger, capacity exhausted at peak."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '60 Sessions'
$Severity       = 'P3'
$Recommendation = "Production pools: idle timeout 30-60 min + auto-logoff after disconnect 1-4h depending on persona. Test impact on user workflows before tightening."

if (-not (Get-HVRestSession)) { return }

foreach ($p in (Get-HVDesktopPool)) {
    $s = $p.session_settings
    if (-not $s) { continue }
    [pscustomobject]@{
        Pool                          = $p.display_name
        DisconnectedSessionTimeoutPolicy = $s.disconnected_session_timeout_policy
        DisconnectedSessionTimeoutMin = $s.disconnected_session_timeout_minutes
        EmptySessionTimeoutPolicy     = $s.empty_session_timeout_policy
        EmptySessionTimeoutMin        = $s.empty_session_timeout_minutes
        LogoffAfterDisconnect         = $s.logoff_after_disconnect_policy
        AllowMultipleSessions         = $s.allow_multiple_sessions_per_user
        Note = if ($s.disconnected_session_timeout_policy -eq 'NEVER' -and $s.logoff_after_disconnect_policy -eq 'NEVER') { 'No reclamation policy - capacity at risk' } else { '' }
    }
}

$TableFormat = @{
    Note = { param($v,$row) if ($v -match 'risk') { 'warn' } else { '' } }
}
