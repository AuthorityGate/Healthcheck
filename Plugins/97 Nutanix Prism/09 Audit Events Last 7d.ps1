# Start of Settings
$LookbackHours = 168  # 7 days
# End of Settings

$Title          = "Nutanix Audit Events (last 7 days)"
$Header         = "[count] administrative action(s) recorded in the last 7 days"
$Comments       = "Who-did-what audit log from Prism. Useful for change-correlation when something stops working ('did anyone touch this cluster overnight?') and for compliance reviews."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "Info"
$Recommendation = "Unfamiliar admin accounts, mass-revert operations, or cluster-config changes outside the change-window are red flags. Prism audit feeds typically retain 30 days; export to SIEM for long-term storage."

if (-not (Get-NTNXRestSession)) { return }
$events = @(Get-NTNXAudit)
if (-not $events) {
    [pscustomobject]@{ Note='No audit events available (or view_audit permission missing).' }
    return
}
$cutoff = [DateTimeOffset]::UtcNow.AddHours(-$LookbackHours).ToUnixTimeMilliseconds() * 1000

$rendered = 0
foreach ($e in $events) {
    $when = if ($e.creation_time) { [long]$e.creation_time } else { 0 }
    if ($when -lt $cutoff) { continue }
    [pscustomobject]@{
        WhenUtc       = if ($when) { [datetimeoffset]::FromUnixTimeMilliseconds([long]$when / 1000).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') } else { '' }
        User          = $e.user
        Operation     = $e.operation_type
        Status        = $e.status
        AffectedEntity = if ($e.affected_entities) { ($e.affected_entities | ForEach-Object { $_.name } | Select-Object -First 3) -join '; ' } else { '' }
        ClientType    = $e.client_type
        SourceIP      = $e.source_ip
    }
    $rendered++
    if ($rendered -ge 500) { break }
}
if ($rendered -eq 0) { [pscustomobject]@{ Note='No admin actions in window.' } }

$TableFormat = @{
    Status = { param($v,$row) if ($v -match 'SUCCESS|COMPLETE') { 'ok' } elseif ($v -match 'FAIL|ERROR') { 'bad' } elseif ($v) { 'warn' } else { '' } }
}
