# Start of Settings
# End of Settings

$Title          = 'App Volumes Assignments'
$Header         = '[count] active assignment(s)'
$Comments       = 'Per-user / per-group AV package assignments. Sized comparison helps spot orphaned assignments.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'Info'
$Recommendation = 'Audit assignments quarterly. Remove for departed users.'

if (-not (Get-AVRestSession)) { return }
$a = Get-AVAssignment
if (-not $a) { return }
foreach ($x in $a.assignments) {
    [pscustomobject]@{
        Type      = $x.entity_type
        Entity    = $x.entity_name
        Package   = $x.package_name
        Marker    = $x.marker_name
        Mount     = $x.mount_prefix
    }
}
