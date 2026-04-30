# Start of Settings
# End of Settings

$Title          = 'Machines Without Recent Heartbeat'
$Header         = '[count] machine(s) without agent heartbeat in 60+ minutes'
$Comments       = "Reference: 'Machine States' (Horizon docs). Machines with no recent heartbeat appear as AGENT_UNREACHABLE in console after the timeout."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '50 Machines'
$Severity       = 'P1'
$Recommendation = 'Investigate Horizon Agent service on each. Reboot if unresponsive.'

if (-not (Get-HVRestSession)) { return }
$m = Get-HVMachine
if (-not $m) { return }
$cutoff = ([DateTimeOffset](Get-Date).AddMinutes(-60)).ToUnixTimeMilliseconds()
foreach ($x in $m) {
    if ($x.last_heartbeat_time -and $x.last_heartbeat_time -lt $cutoff) {
        $when = (Get-Date '1970-01-01').AddMilliseconds($x.last_heartbeat_time).ToLocalTime()
        [pscustomobject]@{ Machine=$x.name; State=$x.machine_state; LastHeartbeat=$when; AgeMinutes=[int](((Get-Date) - $when).TotalMinutes) }
    }
}
