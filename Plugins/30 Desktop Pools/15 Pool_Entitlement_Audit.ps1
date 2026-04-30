# Start of Settings
# End of Settings

$Title          = 'Desktop Pool Entitlement Audit'
$Header         = "[count] pool(s) with entitlement details"
$Comments       = "Per-pool entitled users + groups. Surfaces over-broad entitlement (Domain Users on production pool), un-entitled pools (no users assigned), nested-group depth concerns. Probes multiple endpoint variants - the entitlements API path moved between Horizon 7.x, 2206, and 8.6."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '30 Desktop Pools'
$Severity       = 'P3'
$Recommendation = "Production pools should be entitled to specific groups, not Domain Users. Un-entitled pools waste capacity. Nested groups > 3 deep = AD lookup latency."

if (-not (Get-HVRestSession)) { return }

# Resolve entitlements for a single pool by trying every known endpoint
# variant. Returns @{Users=[]; Groups=[]; Source='<path>'; Error=$null} or
# Error populated on total failure.
function Resolve-HVPoolEntitlement {
    param([Parameter(Mandatory)]$PoolId)
    $variants = @(
        # Horizon 8.6+ inventory v2 - returns user/group objects directly
        @{ Path = "/v2/desktop-pools/$PoolId/users"; Mode = 'v2-users' }
        @{ Path = "/v2/desktop-pools/$PoolId/entitlements"; Mode = 'v2-entitlements' }
        # 8.x external API surface (added v0.93.69 - some Horizon 8.6 builds
        # expose entitlements only via /external/v1 even when /v1/* paths exist)
        @{ Path = "/external/v1/entitlements?desktop_pool_id=$PoolId"; Mode = 'external-flat' }
        @{ Path = "/external/v1/desktop-pools/$PoolId/entitlements"; Mode = 'external-pool-scoped' }
        @{ Path = "/external/v1/desktop-pools/$PoolId/users"; Mode = 'external-users' }
        # 2206-2306 split endpoint
        @{ Path = "/v1/entitlements?desktop_pool_id=$PoolId"; Mode = 'v1-flat' }
        # Pre-2206 query-by-id form
        @{ Path = "/v1/entitlements/desktop-pools?id=$PoolId"; Mode = 'v1-legacy' }
        # Direct entitlements collection variant some builds expose
        @{ Path = "/v1/desktop-pools/$PoolId/entitlements"; Mode = 'pool-scoped' }
        # inventory v1
        @{ Path = "/inventory/v1/entitlements?desktop_pool_id=$PoolId"; Mode = 'inventory-flat' }
    )
    $lastError = $null
    foreach ($v in $variants) {
        try {
            $resp = Invoke-HVRest -Path $v.Path -NoPaging -ErrorAction SilentlyContinue
            if ($null -eq $resp) { continue }
            $users = @()
            $groups = @()
            switch ($v.Mode) {
                'v2-users' {
                    # /v2/desktop-pools/{id}/users returns array of {id, type:'USER'|'GROUP', ...}
                    foreach ($r in @($resp)) {
                        if (-not $r) { continue }
                        if ($r.type -eq 'GROUP' -or $r.principal_type -eq 'GROUP') { $groups += $r.id }
                        elseif ($r.type -eq 'USER' -or $r.principal_type -eq 'USER') { $users += $r.id }
                        elseif ($r.id) { $users += $r.id }
                    }
                }
                'v2-entitlements' {
                    foreach ($r in @($resp)) {
                        if (-not $r) { continue }
                        if ($r.user_ids) { $users += @($r.user_ids) }
                        if ($r.group_ids) { $groups += @($r.group_ids) }
                        if ($r.ad_user_or_group_id -and $r.type -eq 'GROUP') { $groups += $r.ad_user_or_group_id }
                        elseif ($r.ad_user_or_group_id) { $users += $r.ad_user_or_group_id }
                    }
                }
                default {
                    # v1-flat / v1-legacy / pool-scoped: shape is either
                    # @{user_ids; group_ids} OR an array thereof
                    foreach ($r in @($resp)) {
                        if (-not $r) { continue }
                        if ($r.user_ids) { $users += @($r.user_ids) }
                        if ($r.group_ids) { $groups += @($r.group_ids) }
                    }
                }
            }
            # Empty payloads from a working endpoint are still valid (some
            # pools genuinely have no entitlements). Only fall through if
            # the endpoint itself errored.
            return @{
                Users  = @($users | Where-Object { $_ } | Select-Object -Unique)
                Groups = @($groups | Where-Object { $_ } | Select-Object -Unique)
                Source = $v.Path
                Error  = $null
            }
        } catch {
            $lastError = $_.Exception.Message
            continue
        }
    }
    return @{ Users = @(); Groups = @(); Source = '(none)'; Error = $lastError }
}

foreach ($p in (Get-HVDesktopPool)) {
    $r = Resolve-HVPoolEntitlement -PoolId $p.id
    $userCount  = @($r.Users).Count
    $groupCount = @($r.Groups).Count
    $note = ''
    if ($r.Error -and ($userCount + $groupCount -eq 0)) {
        $note = "Entitlement query failed: $($r.Error)"
    } elseif ($userCount + $groupCount -eq 0) {
        $note = 'POOL HAS NO ENTITLEMENTS'
    }
    [pscustomobject]@{
        Pool        = $p.display_name
        Type        = $p.type
        UserCount   = $userCount
        GroupCount  = $groupCount
        Total       = $userCount + $groupCount
        Source      = $r.Source
        Note        = $note
    }
}

$TableFormat = @{
    Total = { param($v,$row) if ("$v" -eq '0' -or $v -eq 0) { 'warn' } else { '' } }
    Note  = { param($v,$row) if ($v -match 'NO ENTITLEMENTS') { 'bad' } elseif ($v -match 'failed') { 'bad' } else { '' } }
}
