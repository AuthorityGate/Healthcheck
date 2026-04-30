# Start of Settings
# End of Settings

$Title          = 'vCenter Administrator Account Distribution'
$Header         = '[count] account(s) holding administrative privilege at root'
$Comments       = 'Inventory of every principal with admin-level role (Administrator role or System.Read+System.Anonymous+other) at the root inventory level. Single shared admin = no per-person attribution; too many admins = blast-radius problem.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Each named admin should be an AD account in a dedicated group; group permissioned at root with the Administrator role. Avoid local SSO admin accounts beyond Administrator@vsphere.local. Rotate the SSO admin password per policy.'

if (-not $Global:VCConnected) { return }

# Walk every permission at every entity, surface those with the Administrator role.
$adminPerms = @()
try {
    $authMgr = Get-View 'AuthorizationManager' -ErrorAction Stop
    foreach ($r in $authMgr.RoleList) {
        if ($r.Name -eq 'Admin' -or $r.Name -match 'Administrator') {
            $rid = $r.RoleId
            $perms = Get-VIPermission -ErrorAction SilentlyContinue | Where-Object { $_.Role -eq $r.Name }
            foreach ($p in $perms) {
                $adminPerms += [pscustomobject]@{
                    Principal  = $p.Principal
                    Role       = $p.Role
                    Entity     = $p.Entity.Name
                    EntityType = $p.EntityId.Type
                    Propagate  = $p.Propagate
                    IsGroup    = $p.IsGroup
                }
            }
        }
    }
} catch { }

$adminPerms | Sort-Object Principal, Entity

$TableFormat = @{
    IsGroup = { param($v,$row) if ($v -ne $true) { 'warn' } else { '' } }
}
