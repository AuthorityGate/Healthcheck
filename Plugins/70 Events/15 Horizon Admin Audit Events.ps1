# Start of Settings
# Look-back window in days. Increase for sparse environments.
$LookbackDays = 7
$MaxRows = 200
# End of Settings

$Title          = 'Horizon Admin Audit Events (last 7 days)'
$Header         = 'Recent administrator actions captured by the event database'
$Comments       = "Connection Server records every admin action - role assignment changes, pool creation / deletion, push image, license edits, disconnects. This audit window surfaces the last 7 days. Required for change-control evidence + any incident-response timeline. Empty result = either nobody touched the environment OR the event DB is offline (cross-check with Event Database Status plugin)."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '70 Events'
$Severity       = 'Info'
$Recommendation = 'Forward Horizon admin events to your SIEM via the Event database / syslog. Daily review of high-impact actions (role assignment, license changes, pool deletes, disconnect-and-logoff broadcasts).'

if (-not (Get-HVRestSession)) { return }

$since = (Get-Date).AddDays(-$LookbackDays).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
# Try the audit-events endpoint first; fall back to /v2/audit-events; then /v1/external/audit-events.
$ev = $null
foreach ($path in @("/v1/external/audit-events?filter=time%20gt%20'$since'", "/v2/audit-events?filter=time%20gt%20'$since'", "/v1/audit-events?filter=time%20gt%20'$since'")) {
    try {
        $ev = Invoke-HVRest -Path $path -ErrorAction Stop
        if ($ev) { break }
    } catch { }
}
if (-not $ev) {
    [pscustomobject]@{ Note='Audit Events endpoint not reachable. The Connection Server may not expose this in your Horizon version, OR the audit account lacks Administrators (Read-only) role.' }
    return
}

$rows = @($ev | Select-Object -First $MaxRows)
$adminEvents = @($rows | Where-Object {
    "$($_.severity)" -match 'INFO|WARN|ERROR|AUDIT' -and (
        "$($_.module)" -match 'ADMIN|MANAGEMENT|CONFIG' -or
        "$($_.event_type)" -match 'ADMIN|ROLE|PERMISSION|LICENSE|POOL|FARM|RECOMPOSE|PUSH|DISCONNECT|LOGOFF'
    )
})
if ($adminEvents.Count -eq 0) {
    [pscustomobject]@{ Note="OK (no administrator actions in last $LookbackDays days, or events fell outside admin module filter)" }
    return
}

foreach ($e in $adminEvents) {
    [pscustomobject]@{
        Time      = if ($e.time) { ([datetime]$e.time).ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
        Severity  = "$($e.severity)"
        Type      = "$($e.event_type)"
        Module    = "$($e.module)"
        UserName  = if ($e.user_name) { "$($e.user_name)" } elseif ($e.user_sid) { "$($e.user_sid)" } else { '' }
        Source    = "$($e.source)"
        Message   = if ($e.message) { "$($e.message)".Substring(0, [Math]::Min(200, "$($e.message)".Length)) } else { '' }
    }
}

$TableFormat = @{
    Severity = { param($v,$row) if ("$v" -eq 'ERROR') { 'bad' } elseif ("$v" -match 'WARN|AUDIT_FAIL') { 'warn' } else { '' } }
}
