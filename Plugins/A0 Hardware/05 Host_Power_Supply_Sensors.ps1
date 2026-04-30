# Start of Settings
# End of Settings

$Title          = 'Host Power Supply Sensors'
$Header         = '[count] host(s) with PSU sensor != green'
$Comments       = 'Reference: KB 2074907. PSU red sensor often follows imminent rail failure.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'P1'
$Recommendation = 'Replace PSU. Confirm dual-feed power chain.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $hi = $_.ExtensionData.Runtime.HealthSystemRuntime
    if (-not $hi) { return }
    foreach ($s in $hi.SystemHealthInfo.NumericSensorInfo) {
        if (($s.Name -match 'Power Supply|PSU') -and $s.HealthState.Key -ne 'green') {
            [pscustomobject]@{ Host=$_.Name; Sensor=$s.Name; Status=$s.HealthState.Key; Reading=$s.CurrentReading }
        }
    }
}
