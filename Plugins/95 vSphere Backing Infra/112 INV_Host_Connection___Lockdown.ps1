# Start of Settings
# End of Settings

$Title          = 'Host Connection / Lockdown'
$Header         = 'Per-host connection state + lockdown mode'
$Comments       = 'Connection state, power state, in-maintenance, lockdown mode, exit standby state. Quick health snapshot.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'Info'
$Recommendation = "Anything other than 'Connected' + 'PoweredOn' should be intentional."

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        Host           = $_.Name
        ConnectionState = $_.ConnectionState
        PowerState     = $_.PowerState
        InMaintenanceMode = $_.ExtensionData.Runtime.InMaintenanceMode
        Lockdown       = $_.ExtensionData.Config.LockdownMode
        StandbyMode    = $_.ExtensionData.Runtime.StandbyMode
        DasState       = $_.ExtensionData.Runtime.DasHostState.State
    }
}
