# Start of Settings
# End of Settings

$Title          = 'Pool Image Push / Recompose State'
$Header         = "[count] pool(s) with active or pending image push"
$Comments       = "Surfaces every pool currently in image-push state (recomposing). Long-running push = stuck = clones may be inconsistent. Without monitoring, stuck pushes go unnoticed."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '30 Desktop Pools'
$Severity       = 'P2'
$Recommendation = "Push lasting > 4h is suspicious. Cancel + investigate. Verify capacity headroom before relaunching push."

if (-not (Get-HVRestSession)) { return }

# Probe multiple endpoints. Different Horizon builds expose this data at:
#   - /v1/monitor/desktop-pool-tasks (older)
#   - /v1/monitor/push-images (2206+)
#   - /v1/desktop-pools/{id}/push-images (per-pool)
$pushes = $null
foreach ($p in @(
    '/v1/monitor/push-images',
    '/v1/monitor/desktop-pool-tasks',
    '/monitor/v1/push-images'
)) {
    try { $pushes = Invoke-HVRest -Path $p; if ($pushes -and @($pushes).Count -gt 0) { break } } catch { }
}

# Per-pool fallback if no global endpoint answered
if (-not $pushes -or @($pushes).Count -eq 0) {
    $perPool = New-Object System.Collections.ArrayList
    foreach ($pool in @(Get-HVDesktopPool)) {
        if (-not $pool -or -not $pool.id) { continue }
        try {
            $r = Get-HVDesktopPoolPushImage -Id $pool.id
            if ($r) { $null = $perPool.AddRange(@($r)) }
        } catch { }
    }
    if ($perPool.Count -gt 0) { $pushes = $perPool.ToArray() }
}

if (-not $pushes -or @($pushes).Count -eq 0) { return }

# Filter to active states only - skip COMPLETE / CANCELED / FAILED rows.
$active = @($pushes | Where-Object {
    $st = $_.status; if (-not $st) { $st = $_.state }
    $st -match 'PENDING|RUNNING|IN_PROGRESS|SCHEDULED|STARTED|ACTIVE'
})
if ($active.Count -eq 0) { return }

foreach ($t in $active) {
    if (-not $t) { continue }
    $startMs = if ($t.start_time) { $t.start_time } elseif ($t.started_at) { $t.started_at } else { $null }
    $started = if ($startMs) { try { (Get-Date '1970-01-01').AddMilliseconds([int64]$startMs) } catch { $null } } else { $null }
    $age = if ($started) { [int]((Get-Date) - $started).TotalMinutes } else { $null }

    [pscustomobject]@{
        Pool      = if ($t.desktop_pool_id) { $t.desktop_pool_id } elseif ($t.pool_id) { $t.pool_id } elseif ($t.pool_name) { $t.pool_name } else { '' }
        Task      = if ($t.task_type) { $t.task_type } elseif ($t.operation) { $t.operation } else { '' }
        Status    = if ($t.status) { $t.status } elseif ($t.state) { $t.state } else { '' }
        Progress  = if ($null -ne $t.progress) { $t.progress } elseif ($t.percent_complete) { $t.percent_complete } else { '' }
        StartedUtc = if ($started) { $started.ToString('yyyy-MM-dd HH:mm') } else { '' }
        AgeMinutes= $age
        Note      = if ($age -ne $null -and $age -gt 240) { 'Long-running push - investigate.' } else { '' }
    }
}

$TableFormat = @{
    AgeMinutes = { param($v,$row) if ($v -ne $null -and $v -gt 240) { 'bad' } elseif ($v -ne $null -and $v -gt 120) { 'warn' } else { '' } }
}
