# Start of Settings
# End of Settings

$Title          = "Pool Refresh / Recompose Schedule"
$Header         = "Per-pool image-refresh policy + push schedule (every pool listed)"
$Comments       = "Refresh = OS volume rolled back to the parent snapshot (linked-clone) or the image base (instant-clone). Recompose = same but with a NEW parent snapshot. Without a periodic refresh schedule, full-clone pools accumulate drift (paged DLLs, agent updates, profile detritus) and instant-clone pools may carry over staged updates that haven't taken effect."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "30 Desktop Pools"
$Severity       = "P3"
$Recommendation = "Linked-clone pools: refresh on every logoff OR weekly. Full-clone pools: schedule recompose monthly when an image change is published. Instant-clone pools auto-refresh on logoff but a STAGED snapshot only takes effect on next REFRESH or PUSH IMAGE - confirm push completed without errors."

if (-not (Get-HVRestSession)) { return }
$pools = @(Get-HVDesktopPool)
if (-not $pools) { return }

function Get-HVPoolNested {
    param($Pool, [string[]]$Paths)
    foreach ($p in $Paths) {
        $segs = $p -split '\.'
        $cur = $Pool
        $ok = $true
        foreach ($s in $segs) {
            if ($null -eq $cur) { $ok = $false; break }
            try { $cur = $cur.$s } catch { $ok = $false; break }
            if ($null -eq $cur) { $ok = $false; break }
        }
        if ($ok -and $null -ne $cur) { return $cur }
    }
    return $null
}

foreach ($p in $pools) {
    if (-not $p) { continue }
    $name = if ($p.name) { "$($p.name)" } else { "$($p.id)" }
    $poolType = if ($p.type) { "$($p.type)" } else { '' }
    $provType = if ($p.provisioning_type) { "$($p.provisioning_type)" } else { '' }

    $refreshPolicy = Get-HVPoolNested $p @(
        'desktop_settings.logoff_settings.refresh_policy',
        'refresh_policy',
        'pattern_naming_settings.refresh_policy'
    )
    $refreshDays = Get-HVPoolNested $p @(
        'desktop_settings.logoff_settings.refresh_period_days_count',
        'refresh_period_days_count',
        'pattern_naming_settings.refresh_period_days_count'
    )
    $refreshGrace = Get-HVPoolNested $p @(
        'desktop_settings.logoff_settings.refresh_grace_period_minutes',
        'refresh_grace_period_minutes'
    )
    $parentVM = Get-HVPoolNested $p @(
        'vcenter_provisioning_settings.virtual_center_provisioning_data.parent_vm',
        'pattern_naming_settings.parent_vm',
        'parent_vm',
        'instant_clone_provisioning_settings.parent_vm'
    )
    $parentSnap = Get-HVPoolNested $p @(
        'vcenter_provisioning_settings.virtual_center_provisioning_data.snapshot',
        'snapshot',
        'instant_clone_provisioning_settings.snapshot'
    )
    $pushState = Get-HVPoolNested $p @(
        'pending_image_state',
        'image_management.pending_image.state'
    )
    $stagedSnap = Get-HVPoolNested $p @(
        'image_management.pending_image.snapshot',
        'pending_snapshot'
    )

    $status = if (-not $refreshPolicy -and "$provType" -match 'INSTANT') { 'INFO (instant-clone, refresh on logoff)' }
              elseif (-not $refreshPolicy) { 'NO POLICY' }
              elseif ("$refreshPolicy" -match 'NEVER') { 'WARN (refresh disabled)' }
              else { "OK ($refreshPolicy)" }

    [pscustomobject]@{
        Pool             = $name
        Type             = $poolType
        Provisioning     = $provType
        RefreshPolicy    = if ($refreshPolicy) { "$refreshPolicy" } else { '' }
        RefreshDays      = if ($refreshDays) { $refreshDays } else { '' }
        RefreshGraceMin  = if ($refreshGrace) { $refreshGrace } else { '' }
        ParentVM         = if ($parentVM) { "$parentVM" } else { '' }
        CurrentSnapshot  = if ($parentSnap) { "$parentSnap" } else { '' }
        PendingPushState = if ($pushState) { "$pushState" } else { '' }
        StagedSnapshot   = if ($stagedSnap) { "$stagedSnap" } else { '' }
        Status           = $status
    }
}

$TableFormat = @{
    RefreshPolicy = { param($v,$row) if ("$v" -match 'NEVER') { 'warn' } else { '' } }
    Status        = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'WARN|NO POLICY') { 'warn' } else { '' } }
}
