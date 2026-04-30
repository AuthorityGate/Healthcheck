# Start of Settings
# End of Settings

$Title          = 'Long-Active Sessions'
$Header         = '[count] session(s) actively connected longer than 12 hours'
$Comments       = 'Sessions running > 12h often indicate broken logoff GPO or service-account misuse.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '60 Sessions'
$Severity       = 'P3'
$Recommendation = "Verify Horizon Global Settings -> 'Forcibly disconnect after' is set, and AD user policy enforces password change."

if (-not (Get-HVRestSession)) { return }
$s = Get-HVSession
if (-not $s) { return }
$cutoff = ([DateTimeOffset](Get-Date).AddHours(-12)).ToUnixTimeMilliseconds()
$s | Where-Object { $_.session_state -eq 'CONNECTED' -and $_.start_time -and $_.start_time -lt $cutoff } | ForEach-Object {
    [pscustomobject]@{
        User      = $_.user_name
        Machine   = $_.machine_name
        Pool      = $_.desktop_pool_name
        Started   = (Get-Date '1970-01-01').AddMilliseconds($_.start_time).ToLocalTime()
        AgeHours  = [int](((Get-Date) - (Get-Date '1970-01-01').AddMilliseconds($_.start_time).ToLocalTime()).TotalHours)
    }
}

