# Start of Settings
# End of Settings

$Title          = 'Failed Authentications (last 24h)'
$Header         = "[count] failed-auth event(s) in the last 24 hours"
$Comments       = "Sum of authentication-failure events from the Horizon Events DB. Spike from a single IP/user = brute-force; broad spike = AD/RADIUS/SAML misconfiguration. Trend daily."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '70 Events'
$Severity       = 'P2'
$Recommendation = "Investigate spikes vs baseline. Single-IP burst = block IP at firewall. Broad spike = check auth pipeline (AD, RADIUS, SAML). Forward to SIEM for trending."

if (-not (Get-HVRestSession)) { return }

$since = ([DateTimeOffset](Get-Date).AddHours(-24)).ToUnixTimeMilliseconds()

try {
    $events = Invoke-HVRest -Path "/v1/external/events?filter=time%20ge%20$since%20and%20event_type%20eq%20'BROKER_USER_AUTHFAILED_TUNNELED'&size=200" -NoPaging
} catch { return }

if (-not $events -or @($events).Count -eq 0) { return }

# Group by (user + source)
@($events) | Group-Object { "$($_.user_id)_$($_.client_id)" } | ForEach-Object {
    $sample = $_.Group[0]
    [pscustomobject]@{
        User      = $sample.user_id
        Source    = $sample.client_id
        FailCount = $_.Count
        FirstSeen = if ($_.Group | ForEach-Object {$_.time} | Sort-Object | Select-Object -First 1) {
            ((Get-Date '1970-01-01').AddMilliseconds([int64]$_.time)).ToString('yyyy-MM-dd HH:mm')
        } else { '' }
        LastSeen  = if ($_.Group | ForEach-Object {$_.time} | Sort-Object -Descending | Select-Object -First 1) {
            ((Get-Date '1970-01-01').AddMilliseconds([int64]$_.time)).ToString('yyyy-MM-dd HH:mm')
        } else { '' }
        Severity  = if ($_.Count -gt 20) { 'HIGH' } elseif ($_.Count -gt 5) { 'MEDIUM' } else { 'LOW' }
    }
} | Sort-Object FailCount -Descending

$TableFormat = @{
    Severity = { param($v,$row) if ($v -eq 'HIGH') { 'bad' } elseif ($v -eq 'MEDIUM') { 'warn' } else { '' } }
}
