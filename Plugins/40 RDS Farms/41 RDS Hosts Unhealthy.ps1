# Start of Settings
# End of Settings

$Title          = "RDS Hosts in non-AVAILABLE state"
$Header         = "[count] RDS host(s) not AVAILABLE"
$Comments       = "RDS Servers in any state other than AVAILABLE cannot accept new sessions and reduce farm capacity."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "40 RDS Farms"
$Severity       = "P1"
$Recommendation = "Investigate the agent state on each host (Horizon Console -> Inventory -> Farms -> RDS Hosts). Restart the 'VMware Horizon View Agent' service or reboot if needed."

$rds = Get-HVRdsServer
if (-not $rds) { return }

foreach ($r in $rds) {
    if ($r.agent_state -ne 'AVAILABLE' -or $r.status -ne 'OK') {
        [pscustomobject]@{
            Name        = $r.name
            Farm        = $r.farm_name
            AgentState  = $r.agent_state
            Status      = $r.status
            Sessions    = $r.session_count
            Enabled     = $r.enabled
            AgentVersion = $r.agent_version
            OS          = $r.operating_system
        }
    }
}

$TableFormat = @{
    AgentState = { param($v,$row) if ($v -ne 'AVAILABLE') { 'bad' } else { '' } }
    Status     = { param($v,$row) if ($v -ne 'OK') { 'bad' } else { '' } }
    Enabled    = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
}
