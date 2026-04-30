# Start of Settings
# A disconnected session held this long (hours) is reported.
$DisconnectedThresholdHours = 48
# End of Settings

$Title          = "Long-Disconnected Sessions"
$Header         = "[count] session(s) disconnected longer than $DisconnectedThresholdHours hours"
$Comments       = "Disconnected sessions hold a desktop and consume CCU. The default Global Policy timeout is often Never - verify policy."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "60 Sessions"
$Severity       = "P2"
$Recommendation = "Set 'Disconnected sessions: Never' to a finite value (e.g. 8h) on Global Settings or per pool, and reset orphan desktops."

$s = Get-HVSession
if (-not $s) { return }

$cutoffMs = ([DateTimeOffset](Get-Date).AddHours(-$DisconnectedThresholdHours)).ToUnixTimeMilliseconds()

$s | Where-Object {
    $_.session_state -eq 'DISCONNECTED' -and $_.disconnected_time -and $_.disconnected_time -lt $cutoffMs
} | ForEach-Object {
    $when = (Get-Date '1970-01-01').AddMilliseconds($_.disconnected_time).ToLocalTime()
    [pscustomobject]@{
        User              = $_.user_name
        Machine           = $_.machine_name
        Pool              = $_.desktop_pool_name
        DisconnectedSince = $when
        AgeHours          = [int]((Get-Date) - $when).TotalHours
        Protocol          = $_.session_protocol
        Client            = $_.client_name
    }
} | Sort-Object DisconnectedSince
