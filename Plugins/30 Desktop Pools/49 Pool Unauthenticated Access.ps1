# Start of Settings
# End of Settings

$Title          = "Pool Unauthenticated / Anonymous Access"
$Header         = "Pools with anonymous launch enabled (every pool listed)"
$Comments       = "Anonymous (Unauthenticated) Access lets users launch a desktop without entering credentials, by mapping a configured anonymous user to a published pool. Useful for kiosks; very high risk if accidentally enabled on a production pool. Only Connection Servers explicitly configured for Unauthenticated Access permit it - lists every pool's setting so operators can audit."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "30 Desktop Pools"
$Severity       = "P1"
$Recommendation = "Disable anonymous access on every pool that does not specifically require it. If kiosk pools exist, restrict the configured anonymous user to a non-privileged AD account, scope the kiosk pool's network range to the kiosk LAN, and audit the connection server's 'Unauthenticated Access' tab quarterly."

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
    $allowAnon = Get-HVPoolNested $p @(
        'desktop_settings.support_unauthenticated_access',
        'allow_unauthenticated_access',
        'unauthenticated_access_enabled',
        'desktop_settings.unauthenticated_access_enabled'
    )
    $allowMulti = Get-HVPoolNested $p @(
        'desktop_settings.allow_multiple_sessions_per_user',
        'allow_multiple_sessions_per_user'
    )
    $forced  = Get-HVPoolNested $p @('desktop_settings.support_unauthenticated_access_for_unauthenticated_users')
    $defAccount = Get-HVPoolNested $p @('desktop_settings.unauthenticated_access_default_user','unauthenticated_default_user')

    $isAnon = [bool]$allowAnon
    $status = if ($isAnon) { 'BAD (anonymous launch enabled)' } else { 'OK' }
    [pscustomobject]@{
        Pool                   = $name
        Type                   = if ($p.type) { "$($p.type)" } else { '' }
        UnauthenticatedAccess  = $isAnon
        DefaultAnonymousUser   = if ($defAccount) { "$defAccount" } else { '' }
        MultipleSessionsAllowed= if ($null -ne $allowMulti) { [bool]$allowMulti } else { '' }
        Status                 = $status
    }
}

$TableFormat = @{
    UnauthenticatedAccess = { param($v,$row) if ($v -eq $true) { 'bad' } else { '' } }
    Status                = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -match 'BAD') { 'bad' } else { '' } }
}
