# Start of Settings
$LookbackHours = 24
# End of Settings

$Title          = "Nutanix Failed Tasks (last 24h)"
$Header         = "[count] failed task(s) in the last 24 hours"
$Comments       = "Tasks in FAILED / ABORTED / CANCELED state from /tasks/list filtered to the lookback window. The Nutanix counterpart to vCenter Recently_Failed_Tasks. Repeated failures of the same task type signal a config or capacity gap."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "P3"
$Recommendation = "Failed VmCloneIntent / VmRestoreFromSnapshot operations: usually capacity. Failed StorageContainerUpdate: name conflict or RF change attempt during in-flight rebuild. Pattern of failures across many entities = cluster-wide issue (often LCM mid-flight)."

if (-not (Get-NTNXRestSession)) { return }
$tasks = @(Get-NTNXTask)
if (-not $tasks) {
    [pscustomobject]@{ Note='No tasks returned (or view_task permission missing).' }
    return
}
$cutoff = [DateTimeOffset]::UtcNow.AddHours(-$LookbackHours).ToUnixTimeMilliseconds() * 1000

$rendered = 0
foreach ($t in $tasks) {
    if ($t.status -notin @('FAILED','ABORTED','CANCELED','CANCELLED')) { continue }
    $when = if ($t.creation_time) { [long]$t.creation_time } else { 0 }
    if ($when -lt $cutoff) { continue }
    [pscustomobject]@{
        WhenUtc      = if ($when) { [datetimeoffset]::FromUnixTimeMilliseconds([long]$when / 1000).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') } else { '' }
        Operation    = $t.operation_type
        Status       = $t.status
        Cluster      = if ($t.cluster_reference) { $t.cluster_reference.name } else { '' }
        EntityKind   = if ($t.entity_reference_list) { $t.entity_reference_list[0].kind } else { '' }
        EntityName   = if ($t.entity_reference_list) { $t.entity_reference_list[0].name } else { '' }
        ErrorCode    = if ($t.error_code_list) { ($t.error_code_list -join '; ') } else { '' }
        ErrorMessage = if ($t.error_detail) { $t.error_detail.Substring(0, [Math]::Min(180, $t.error_detail.Length)) } else { '' }
    }
    $rendered++
    if ($rendered -ge 200) { break }
}
if ($rendered -eq 0) { [pscustomobject]@{ Note='No failed tasks in window.' } }

$TableFormat = @{
    Status = { param($v,$row) if ($v -match 'FAILED|ABORTED') { 'bad' } elseif ($v -match 'CANCEL') { 'warn' } else { '' } }
}
