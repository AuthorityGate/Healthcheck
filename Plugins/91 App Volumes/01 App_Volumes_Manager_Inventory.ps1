# Start of Settings
# End of Settings

$Title          = 'App Volumes Manager Inventory'
$Header         = '[count] App Volumes Manager(s) registered with this pod'
$Comments       = 'All AV Managers in the deployment, version, and clustering peer count.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '91 App Volumes'
$Severity       = 'Info'
$Recommendation = 'Confirm replication peers expected per the design document. AV 4.x supports active/active manager clusters.'
$RequiredBackend = 'AppVolumes'

if (-not (Get-AVRestSession)) { return }
$mgrs = Get-AVManager
if (-not $mgrs) { return }
foreach ($m in $mgrs.managers) {
    [pscustomobject]@{
        Name           = $m.name
        Version        = $m.version
        InternalVersion = $m.internal_version
        Mode           = $m.mode
        Status         = $m.status
        ServerStatus   = $m.server_status
        Domain         = $m.domain
    }
}
