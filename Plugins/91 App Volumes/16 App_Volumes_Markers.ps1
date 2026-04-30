# Start of Settings
# End of Settings

$Title          = 'App Volumes Markers'
$Header         = '[count] AV marker(s) configured'
$Comments       = 'Markers point to current package version per app. Stale markers or missing markers cause assignment errors.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P3'
$Recommendation = 'Audit marker -> package mapping; remove markers pointing to deleted packages.'

if (-not (Get-AVRestSession)) { return }
$mk = Get-AVAppMarker
if (-not $mk) { return }
foreach ($m in $mk.app_markers) {
    [pscustomobject]@{
        Marker  = $m.name
        Package = $m.app_package_name
        Note    = $m.note
        State   = $m.state
    }
}
