# Start of Settings
# End of Settings

$Title          = 'Pending Host Reboot'
$Header         = '[count] host(s) with pending reboot'
$Comments       = 'Hosts with pending reboot post-patch leave protections off until they reboot.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P1'
$Recommendation = 'Schedule a maintenance-mode reboot for each.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $r = $_.ExtensionData.Runtime.RebootRequired
    if ($r) {
        [pscustomobject]@{ Host=$_.Name; RebootRequired=$r; Cluster=$_.Parent.Name }
    }
}
