# Start of Settings
# End of Settings

$Title          = 'Inactive vCenter Roles'
$Header         = '[count] custom role(s) with no permission grants'
$Comments       = 'Custom roles never assigned to any principal are clutter that increases admin error.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Audit and remove unused roles.'

if (-not $Global:VCConnected) { return }
$assigned = @{}
foreach ($p in (Get-VIPermission -ErrorAction SilentlyContinue)) { $assigned[$p.Role] = $true }
foreach ($r in (Get-VIRole -ErrorAction SilentlyContinue)) {
    if (-not $r.IsSystem -and -not $assigned.ContainsKey($r.Name)) {
        [pscustomobject]@{ Role=$r.Name; PrivilegeCount=$r.PrivilegeList.Count }
    }
}
