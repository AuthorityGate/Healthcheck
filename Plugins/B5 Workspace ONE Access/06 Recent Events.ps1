# Start of Settings
$LookbackHours = 24
# End of Settings

$Title          = "vIDM Recent Events"
$Header         = "[count] notable event(s) in the last $LookbackHours h"
$Comments       = "Recent tenant events from /notification/events: failed logins, sync failures, certificate-expiry warnings, admin actions. Equivalent of vCenter Recently Failed Tasks for the IdP layer."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B5 Workspace ONE Access"
$Severity       = "P3"
$Recommendation = "Repeated failed logins from one user = compromised credential or stale-session issue; investigate from the source IP. Connector sync failures = directory bind broken. Cert-expiry events = act before expiration."

if (-not (Get-VIDMRestSession)) { return }
$events = Get-VIDMRecentEvent
if (-not $events -or -not $events.items) {
    [pscustomobject]@{ Note = 'No event items returned (audit endpoint may not be exposed by this tenant version).' }
    return
}

$cutoff = [DateTimeOffset]::UtcNow.AddHours(-$LookbackHours).ToUnixTimeMilliseconds()
$rendered = 0
foreach ($e in $events.items) {
    $ts = if ($e.eventTimestamp) { [int64]$e.eventTimestamp } else { 0 }
    if ($ts -lt $cutoff) { continue }
    [pscustomobject]@{
        WhenUtc   = if ($ts) { [datetimeoffset]::FromUnixTimeMilliseconds($ts).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') } else { '' }
        Type      = $e.eventType
        Subject   = $e.subject
        Actor     = $e.userId
        SourceIP  = $e.sourceIp
        Outcome   = $e.outcome
        Detail    = if ($e.eventDetails) { ($e.eventDetails | Out-String).Substring(0,[Math]::Min(180, ($e.eventDetails | Out-String).Length)) } else { '' }
    }
    $rendered++
    if ($rendered -ge 200) { break }
}
if ($rendered -eq 0) { [pscustomobject]@{ Note = "No events in the last $LookbackHours hours." } }

$TableFormat = @{
    Outcome = { param($v,$row) if ($v -match 'SUCCESS|OK') { 'ok' } elseif ($v -match 'FAIL|DENIED|ERROR') { 'bad' } elseif ($v) { 'warn' } else { '' } }
}
