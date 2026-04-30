# Start of Settings
# End of Settings

$Title          = "Horizon Administrators and Roles"
$Header         = "[count] admin permission binding(s)"
$Comments       = "Every administrator (user/group) bound to the Horizon pod, with the role granted, scope (access group), and source. Used for least-privilege audits and identifying orphaned admin permissions during AD cleanup."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "10 Connection Servers"
$Severity       = "Info"
$Recommendation = "Remove permissions for AD principals that no longer exist. Keep 'Administrators' role membership tight. Document which group owns the pod so responsibilities are clear during outages."

if (-not (Get-HVRestSession)) { return }

$perms = @(Get-HVAdminPermission)
$roles = @(Get-HVAdminRole)
$users = @(Get-HVAdminUser)
if (-not $perms -and -not $users) { return }

$roleMap = @{}
foreach ($r in $roles) { if ($r.id) { $roleMap[$r.id] = $r.name } }
$userMap = @{}
foreach ($u in $users) { if ($u.id) { $userMap[$u.id] = "$($u.user_or_group_name) ($($u.user_or_group_type))" } }

foreach ($p in $perms) {
    [pscustomobject]@{
        Principal = if ($p.user_or_group_id) { Resolve-HVId $p.user_or_group_id $userMap } else { $p.user_or_group_id }
        Role      = if ($p.role_id) { Resolve-HVId $p.role_id $roleMap } else { '' }
        Scope     = if ($p.access_group_id) { $p.access_group_id } else { 'Root' }
        IsCustom  = [bool]$p.is_custom
        IsApp     = [bool]$p.is_app_admin
    }
}
