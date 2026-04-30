# Start of Settings
# End of Settings

$Title          = 'App Volumes Marker Currency'
$Header         = "[count] AV marker(s) inventoried"
$Comments       = "Markers point assignments at the 'current' package version. Stale markers = users on old package version. Audit which marker points where + last update time."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P3'
$Recommendation = "Markers should advance when new package version released. Stale marker = old version still attached at logon. Move marker as part of release runbook."

if (-not (Get-AVRestSession)) { return }

try {
    $markers = Invoke-AVRest -Path '/cv_api/markers'
    foreach ($m in @($markers.markers)) {
        [pscustomobject]@{
            Marker         = $m.name
            CurrentTarget  = $m.current_marker_id
            CurrentPackage = if ($m.current_package) { $m.current_package.name } else { '' }
            Owner          = $m.owner
            CreatedAt      = $m.created_at
            UpdatedAt      = $m.updated_at
        }
    }
} catch { }
