# Start of Settings
# End of Settings

$Title          = 'Pod Consolidation Report'
$Header         = 'How the runner sees this pod (single vs. multi-pod / replica vs. distinct pod)'
$Comments       = @"
Diagnostic for the "every plugin emitted 4x" symptom on a 4-CS replica pod.
Shows for each connected Connection Server:
  - what /v1/pods returned (id, name, raw or synthesized)
  - the pod-key the runner used to dedupe
  - whether the runner treated all CSes as one pod (correct) or several (regression)

A 4-CS replica pair must consolidate to a single pod-key. If this row reports
'distinct pods=4' for a known-replica pair, the per-pod dedup in Start-HorizonHealthCheckGUI.ps1 has regressed.
"@
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'Info'
$Recommendation = "If 'PodKey' is unique per CS but you know they're replicas, inspect Get-HVPod output above - Horizon 8.6 returns empty pod objects, which the v0.94.0 Get-HVPod fallback synthesizes into a single 'synth-<server>' key. If the synth key isn't being shared across CSes, the runner is connecting to each CS as if they were independent pods rather than replicas."

$rows = New-Object System.Collections.ArrayList

# Source list: every connected CS the runner knows about. Falls back to the
# operator-typed FQDN list, then to the active session.
$fqdns = New-Object System.Collections.Generic.HashSet[string]
if ($Global:HVConnectedFqdnList) {
    foreach ($f in @($Global:HVConnectedFqdnList)) {
        $t = ([string]$f).Trim()
        if ($t) { [void]$fqdns.Add($t.ToLower()) }
    }
}
if ($Global:HVServer) {
    foreach ($f in @($Global:HVServer -split '[,;\s]+')) {
        $t = ([string]$f).Trim()
        if ($t) { [void]$fqdns.Add($t.ToLower()) }
    }
}
if ($fqdns.Count -eq 0 -and (Get-HVRestSession)) {
    $sess = Get-HVRestSession
    if ($sess.Server) { [void]$fqdns.Add(([string]$sess.Server).ToLower()) }
}
if ($fqdns.Count -eq 0) {
    [pscustomobject]@{
        ConnectionServer = '(no CS connected)'
        PodKey           = ''
        IsLocal          = $false
        Synthesized      = $false
        Note             = 'No Horizon REST session is open. Connect to a Connection Server on the Horizon tab and re-run.'
    }
    return
}

# Walk each connected CS, point the active session at it, query /v1/pods.
$distinctKeys = New-Object System.Collections.Generic.HashSet[string]
foreach ($srv in $fqdns) {
    $key = ''
    $name = ''
    $local = $false
    $synth = $false
    $count = 0
    $note = ''
    try {
        Set-HVActiveSession -Server $srv -ErrorAction SilentlyContinue | Out-Null
        $pods = @(Get-HVPod -ErrorAction SilentlyContinue)
        $count = $pods.Count
        $pickLocal = @($pods | Where-Object { $_.local_pod -eq $true -or $_.localPod -eq $true } | Select-Object -First 1)
        if (-not $pickLocal -or @($pickLocal).Count -eq 0) { $pickLocal = @($pods | Select-Object -First 1) }
        if ($pickLocal -and $pickLocal[0]) {
            $p = $pickLocal[0]
            $key   = if ($p.id)   { "$($p.id)" }   else { '' }
            $name  = if ($p.name) { "$($p.name)" } else { '' }
            $local = ($p.local_pod -eq $true -or $p.localPod -eq $true)
            $synth = ($p.PSObject.Properties['_synthesized'] -and $p._synthesized -eq $true)
            if ($synth) { $note = "$($p._stub_reason) - synthesized pod-key applied so all replica CSes consolidate to one iteration." }
        }
        if (-not $key) { $key = 'unknown-pod' }
    } catch {
        $note = "Get-HVPod threw: $($_.Exception.Message)"
        $key = 'error'
    }
    [void]$distinctKeys.Add($key)
    [void]$rows.Add([pscustomobject]@{
        ConnectionServer = $srv
        PodCount         = $count
        PodKey           = $key
        PodName          = $name
        IsLocal          = $local
        Synthesized      = $synth
        Note             = $note
    })
}

# Summary row at the end so the operator immediately sees the verdict.
$verdict = if ($distinctKeys.Count -le 1) {
    "PASS - $($fqdns.Count) CS(es) consolidate to $($distinctKeys.Count) distinct pod-key. Plugins will run ONCE."
} else {
    "FAIL - $($fqdns.Count) CS(es) report $($distinctKeys.Count) distinct pod-keys. Plugins will run $($distinctKeys.Count)x and emit duplicate rows."
}
[void]$rows.Add([pscustomobject]@{
    ConnectionServer = '(verdict)'
    PodCount         = ''
    PodKey           = "$($distinctKeys.Count) distinct"
    PodName          = ''
    IsLocal          = ''
    Synthesized      = ''
    Note             = $verdict
})

$rows.ToArray()

$TableFormat = @{
    PodKey      = { param($v,$row) if ($v -eq 'unknown-pod' -or $v -eq 'error') { 'bad' } elseif ($v -like 'synth-*') { 'warn' } else { '' } }
    Synthesized = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
    Note        = { param($v,$row) if ($v -like 'FAIL*' -or $v -like '*regression*') { 'bad' } elseif ($v -like 'PASS*') { 'ok' } else { '' } }
}
