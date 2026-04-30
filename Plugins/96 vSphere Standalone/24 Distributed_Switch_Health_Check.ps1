# Start of Settings
# End of Settings

$Title          = 'Distributed Switch Health Check'
$Header         = '[count] distributed switch(es) without health-check enabled'
$Comments       = "Reference: 'vSphere Distributed Switch Health Check'. Detects MTU/teaming/VLAN drift."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'vDS -> Configure -> Health Check -> enable VLAN/MTU + Teaming and Failover.'

if (-not $Global:VCConnected) { return }
Get-VDSwitch -ErrorAction SilentlyContinue | ForEach-Object {
    $hc = $_.ExtensionData.Config.HealthCheckConfig
    $vlan  = ($hc | Where-Object { $_.GetType().Name -like '*VlanMtu*' }).Enable
    $team  = ($hc | Where-Object { $_.GetType().Name -like '*Teaming*' }).Enable
    if (-not $vlan -or -not $team) {
        [pscustomobject]@{ Switch=$_.Name; VlanMtu=$vlan; Teaming=$team }
    }
}
