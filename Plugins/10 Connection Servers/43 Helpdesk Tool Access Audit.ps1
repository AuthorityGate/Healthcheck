# Start of Settings
# End of Settings

$Title          = 'Help Desk Tool Access Audit'
$Header         = 'Roles + administrators with Help Desk privileges'
$Comments       = "The Help Desk Tool gives privileged real-time access: live session shadow, force-disconnect, send message, restart machine. Permissions are managed via Horizon administrator roles + role assignments. Every account with Help Desk Administrator OR Help Desk Administrator (Read Only) role is listed; in production this list should be small + traceable."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'P2'
$Recommendation = 'Limit Help Desk role membership to Tier-1 + Tier-2 EUC Operations groups. Use AD GROUPS not individual users. Pair with Workspace ONE Access conditional-access (require Compliant + MFA) for the Help Desk console URL.'

if (-not (Get-HVRestSession)) { return }
$admins = @(Get-HVAdminUser)
$perms  = @(Get-HVAdminPermission)
$roles  = @(Get-HVAdminRole)
if (-not $admins) {
    [pscustomobject]@{ Note='Get-HVAdminUser returned no rows. Check audit account has Administrators (Read-only) role at root.' }
    return
}
$helpdeskRoleIds = @($roles | Where-Object { "$($_.name)" -match 'Help[\s_-]?desk' } | Select-Object -ExpandProperty id)
if ($helpdeskRoleIds.Count -eq 0) {
    [pscustomobject]@{ Note='No role with name containing "Help Desk" found. May be present under a custom role - audit roles manually.' }
    return
}
$roleNameMap = @{}
foreach ($r in $roles) { if ($r.id) { $roleNameMap[$r.id] = $r.name } }

$found = $false
foreach ($adm in $admins) {
    $name = if ($adm.user_or_group_name) { $adm.user_or_group_name } elseif ($adm.principal) { $adm.principal } else { "$($adm.id)" }
    $isGroup = [bool]$adm.group
    # Permissions for this admin
    $adminPerms = @($perms | Where-Object { $_.user_or_group_id -eq $adm.id -or $_.principal -eq $adm.principal })
    foreach ($pm in $adminPerms) {
        $rid = $pm.role_id
        if ($helpdeskRoleIds -contains $rid) {
            $found = $true
            [pscustomobject]@{
                Principal = $name
                IsGroup   = $isGroup
                Role      = if ($roleNameMap.ContainsKey($rid)) { $roleNameMap[$rid] } else { "$rid" }
                Scope     = if ($pm.access_group_id) { "AccessGroup:$($pm.access_group_id)" } elseif ($pm.federation_access_group_id) { "FederationAG:$($pm.federation_access_group_id)" } else { 'Root' }
                Status    = if ($isGroup) { 'OK (group)' } else { 'WARN (individual user)' }
            }
        }
    }
}
if (-not $found) {
    [pscustomobject]@{ Principal=''; IsGroup=''; Role=''; Scope=''; Status='OK (no Help Desk admins assigned)' }
}

$TableFormat = @{
    IsGroup = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
    Status  = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'WARN') { 'warn' } else { '' } }
}
