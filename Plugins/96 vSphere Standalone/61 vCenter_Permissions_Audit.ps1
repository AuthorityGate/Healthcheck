# Start of Settings
# End of Settings

$Title          = 'vCenter Permissions / Privileged Roles'
$Header         = "[count] over-privileged AD principals at vCenter level"
$Comments       = "Permissions assigned at vCenter root level apply to everything. 'Administrator' role on root = full vSphere takeover. Audit who has it. Tighten over-broad assignments."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P2'
$Recommendation = "Administrator role at root should be: small named admin group + service accounts only. No 'Domain Admins' or wide groups. Use lower roles + delegate at lower scopes."

if (-not $Global:VCConnected) { return }

try {
    foreach ($p in (Get-VIPermission -Entity (Get-Folder -Type Datacenter -NoRecursion | Select-Object -First 1) -ErrorAction SilentlyContinue)) {
        if ($p.Role -match 'Administrator|Admin') {
            [pscustomobject]@{
                Principal = $p.Principal
                Role      = $p.Role
                Entity    = if ($p.Entity) { $p.Entity.Name } else { 'root' }
                Propagate = $p.Propagate
                IsGroup   = $p.IsGroup
                Note      = if ($p.IsGroup -and $p.Principal -match 'Domain Admins|Enterprise Admins|Domain Users') { 'Wide AD group on Administrator - high risk' } else { '' }
            }
        }
    }
} catch { }

$TableFormat = @{
    Note = { param($v,$row) if ($v -match 'high risk') { 'bad' } else { '' } }
}
