# Start of Settings
# End of Settings

$Title          = "Desktop Pool Power Policy + Action Timeouts"
$Header         = "Per-pool power policy, after-logoff action, idle/disconnect handling"
$Comments       = "Power policy controls when Horizon powers down VMs to save host resources. ALWAYS_ON keeps VMs hot (best UX, highest cost); SUSPEND saves RAM but takes 10-30 s to wake; POWERED_OFF saves CPU+RAM, takes 60-120 s. After-logoff action governs whether a VM gets refreshed, recomposed, or deleted on logoff. Lists every pool so operators can verify intent."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "30 Desktop Pools"
$Severity       = "P3"
$Recommendation = "VDI: ALWAYS_ON for full clones; ALWAYS_ON or SUSPEND for instant clones to keep launch < 10 s. RDS hosts: ALWAYS_ON. After-logoff: instant-clone pools should DELETE+REFRESH on logoff; full-clone pools = NONE (persistent). Action timeouts > 60 minutes can pile up un-actioned VMs in a Provisioning state."

if (-not (Get-HVRestSession)) { return }
$pools = @(Get-HVDesktopPool)
if (-not $pools) { return }

function Get-HVPoolNested {
    param($Pool, [string[]]$Paths)
    foreach ($p in $Paths) {
        $segments = $p -split '\.'
        $cur = $Pool
        $ok = $true
        foreach ($s in $segments) {
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
    $powerPol = Get-HVPoolNested $p @(
        'desktop_settings.logoff_settings.power_policy',
        'settings.logoff_settings.power_policy',
        'desktop_settings.power_policy',
        'power_policy',
        'logoff_settings.power_policy'
    )
    $actionLogoff = Get-HVPoolNested $p @(
        'desktop_settings.logoff_settings.automatic_logoff_policy',
        'logoff_policy',
        'desktop_settings.logoff_policy'
    )
    $afterLogoff = Get-HVPoolNested $p @(
        'desktop_settings.logoff_settings.refresh_policy',
        'pattern_naming_settings.refresh_policy',
        'after_logoff_action',
        'desktop_settings.refresh_policy'
    )
    $emptyAction = Get-HVPoolNested $p @(
        'desktop_settings.logoff_settings.empty_session_timeout_policy',
        'desktop_settings.empty_session_timeout_policy',
        'empty_session_timeout_policy'
    )
    $emptyMins   = Get-HVPoolNested $p @(
        'desktop_settings.logoff_settings.empty_session_timeout_minutes',
        'empty_session_timeout_minutes'
    )
    $idleMins    = Get-HVPoolNested $p @(
        'desktop_settings.logoff_settings.automatic_logoff_minutes',
        'automatic_logoff_minutes'
    )

    $status = if (-not $powerPol) { 'NOT QUERIED (path mismatch)' } else { 'OK' }

    [pscustomobject]@{
        Pool                   = $name
        Type                   = $poolType
        PowerPolicy            = if ($powerPol) { "$powerPol" } else { '' }
        AutomaticLogoffPolicy  = if ($actionLogoff) { "$actionLogoff" } else { '' }
        AutoLogoffMinutes      = if ($idleMins) { $idleMins } else { '' }
        AfterLogoffAction      = if ($afterLogoff) { "$afterLogoff" } else { '' }
        EmptySessionPolicy     = if ($emptyAction) { "$emptyAction" } else { '' }
        EmptySessionMinutes    = if ($emptyMins) { $emptyMins } else { '' }
        Status                 = $status
    }
}

$TableFormat = @{
    PowerPolicy = { param($v,$row) if ("$v" -match 'POWERED_OFF') { 'warn' } else { '' } }
    Status      = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } else { 'warn' } }
}
