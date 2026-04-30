# Start of Settings
$WarnIfLastRunOlderThanHours = 48
# End of Settings

$Title          = "Veeam Backup Job Last-Run + Status"
$Header         = "[count] Veeam job(s) inventoried"
$Comments       = "For every backup / replication / agent job: schedule, last run timestamp, last result (Success / Warning / Failed), the protected entity count, the next scheduled run. Job that hasn't run in > 48h with a non-Success last result = silent backup gap."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B7 Backup and DR"
$Severity       = "P1"
$Recommendation = "Failed / warning jobs need triage today. Disabled jobs should be confirmed intentionally disabled (often forgotten after a one-time test). Jobs with NO recent run despite an Active schedule mean Job Manager service stalled - restart Veeam services."

if (-not (Get-VeeamRestSession)) { return }
$jobs = Get-VeeamJob
$states = Get-VeeamJobState
if (-not $jobs -or -not $jobs.data) {
    [pscustomobject]@{ Note = 'No jobs returned (or admin lacks Backup Operator role).' }
    return
}
$stateMap = @{}
if ($states -and $states.data) { foreach ($st in $states.data) { $stateMap[$st.id] = $st } }

$cutoffMs = ((Get-Date).AddHours(-$WarnIfLastRunOlderThanHours)).ToUniversalTime()
foreach ($j in $jobs.data) {
    $st = $stateMap[$j.id]
    $lastRun = $null
    if ($st -and $st.lastRun) { try { $lastRun = [datetime]$st.lastRun } catch { } }
    $ageHours = if ($lastRun) { [int]((Get-Date) - $lastRun).TotalHours } else { $null }
    [pscustomobject]@{
        Job          = $j.name
        Type         = $j.type
        IsDisabled   = [bool]$j.isDisabled
        Schedule     = if ($j.schedule) { $j.schedule.type } else { '(no schedule)' }
        LastRun      = if ($lastRun) { $lastRun.ToString('yyyy-MM-dd HH:mm') } else { '' }
        LastResult   = if ($st) { $st.lastResult } else { '' }
        AgeHours     = $ageHours
        ProtectedItems = if ($st) { $st.protectedObjectsCount } else { '' }
    }
}

$TableFormat = @{
    LastResult = { param($v,$row) if ($v -eq 'Success') { 'ok' } elseif ($v -match 'Warning') { 'warn' } elseif ($v -match 'Failed') { 'bad' } else { '' } }
    AgeHours   = { param($v,$row) if ([int]"$v" -gt 168) { 'bad' } elseif ([int]"$v" -gt 48) { 'warn' } else { '' } }
    IsDisabled = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
}
