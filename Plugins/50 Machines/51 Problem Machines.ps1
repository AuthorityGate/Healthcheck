# Start of Settings
# Machine states that constitute a finding.
$BadStates = @(
    'ERROR','PROVISIONING_ERROR','AGENT_UNREACHABLE','AGENT_ERR_STARTUP_IN_PROGRESS',
    'AGENT_ERR_DISABLED','AGENT_ERR_INVALID_IP','AGENT_ERR_NEED_REBOOT',
    'AGENT_ERR_PROTOCOL_FAILURE','AGENT_ERR_DOMAIN_FAILURE','UNKNOWN','UNASSIGNED_USER_DISCONNECTED'
)
# End of Settings

$Title          = "Machines in problem states"
$Header         = "[count] machine(s) in a non-healthy state"
$Comments       = "Machines in any of these states are unable to broker sessions: $($BadStates -join ', ')."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "50 Machines"
$Severity       = "P1"
$Recommendation = "Per machine, check Horizon Console -> Tasks/Events. Common fixes: reboot, re-publish image, reset agent service, re-add to domain."

$m = Get-HVMachine
if (-not $m) { return }

$m | Where-Object { $_.machine_state -in $BadStates } | ForEach-Object {
    [pscustomobject]@{
        Name         = $_.name
        State        = $_.machine_state
        Pool         = $_.desktop_pool_name
        AgentVersion = $_.agent_version
        DnsName      = $_.dns_name
        AssignedUser = $_.user_name
        OS           = $_.operating_system
        LastError    = $_.message_security
    }
}

$TableFormat = @{
    State = { param($v,$row) 'bad' }
}
