# Start of Settings
# End of Settings

$Title          = 'App Volumes Provisioning Rights'
$Header         = "[count] AD principals with provisioning rights"
$Comments       = "Who can capture / publish / assign / delete App Volumes packages? Over-broad rights = unauthorized package changes. Ideal: small named team via AD groups."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P2'
$Recommendation = "Provisioning rights should be a small named AD group, not Domain Admins or wide group. Audit annually. Document the change-control process for new packages."

if (-not (Get-AVRestSession)) { return }

try {
    $roles = Invoke-AVRest -Path '/cv_api/admin_roles'
    foreach ($r in @($roles.admin_roles)) {
        [pscustomobject]@{
            RoleName    = $r.name
            Members     = if ($r.members) { ($r.members | ForEach-Object { if ($_.name) { $_.name } else { $_.upn } }) -join '; ' } else { '(none)' }
            Permissions = if ($r.permissions) { ($r.permissions -join ', ') } else { '' }
            Note        = if ($r.name -match 'Administrator|Provisioning' -and $r.members.Count -gt 5) { 'Membership > 5 - tighten' } else { '' }
        }
    }
} catch {
    [pscustomobject]@{ RoleName = 'Error'; Members = ''; Permissions = ''; Note = $_.Exception.Message }
}

$TableFormat = @{
    Note = { param($v,$row) if ($v -match 'tighten') { 'warn' } else { '' } }
}
