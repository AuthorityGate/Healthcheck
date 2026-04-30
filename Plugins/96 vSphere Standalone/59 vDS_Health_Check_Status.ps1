# Start of Settings
# End of Settings

$Title          = 'vDS Network Health Check Status'
$Header         = "[count] vDS(s) with health check enabled/disabled"
$Comments       = "vDS Network Health Check detects: VLAN mismatch, MTU mismatch, teaming-policy inconsistency between hosts. Disabled = silent uplink config drift."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = "Enable VLAN/MTU health check on every production vDS. Review results in vSphere Client; address mismatches."

if (-not $Global:VCConnected) { return }

foreach ($vds in (Get-VDSwitch -ErrorAction SilentlyContinue)) {
    $hc = $vds.ExtensionData.Config.HealthCheckConfig
    $vlanMtu = $hc | Where-Object { $_.GetType().Name -eq 'VMwareDVSVlanMtuHealthCheckConfig' }
    $teaming = $hc | Where-Object { $_.GetType().Name -eq 'VMwareDVSTeamingHealthCheckConfig' }

    [pscustomobject]@{
        Switch          = $vds.Name
        VlanMtuEnabled  = if ($vlanMtu) { $vlanMtu.Enable } else { $null }
        TeamingEnabled  = if ($teaming) { $teaming.Enable } else { $null }
        Version         = $vds.Version
        Note            = if ((-not $vlanMtu -or -not $vlanMtu.Enable) -or (-not $teaming -or -not $teaming.Enable)) { 'Health Check disabled - drift will go silent' } else { '' }
    }
}

$TableFormat = @{
    VlanMtuEnabled = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
    TeamingEnabled = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
}
