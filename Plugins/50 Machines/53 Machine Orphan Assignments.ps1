# Start of Settings
# End of Settings

$Title          = 'Orphaned Machine Assignments'
$Header         = '[count] dedicated machine(s) assigned to a user that has not connected in 60+ days'
$Comments       = 'Dedicated assignment + extended absence = orphan capacity. Reclaim it.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '50 Machines'
$Severity       = 'P3'
$Recommendation = 'Console -> Machines -> filter Last Login < (today - 60d) -> Unassign.'

if (-not (Get-HVRestSession)) { return }
$m = Get-HVMachine
if (-not $m) { return }
$cutoff = ([DateTimeOffset](Get-Date).AddDays(-60)).ToUnixTimeMilliseconds()
foreach ($x in $m) {
    if ($x.user_assignment -eq 'DEDICATED' -and $x.last_session_end_time -and $x.last_session_end_time -lt $cutoff -and $x.user_name) {
        [pscustomobject]@{
            Machine     = $x.name
            User        = $x.user_name
            Pool        = $x.desktop_pool_name
            LastSession = (Get-Date '1970-01-01').AddMilliseconds($x.last_session_end_time).ToLocalTime()
        }
    }
}

