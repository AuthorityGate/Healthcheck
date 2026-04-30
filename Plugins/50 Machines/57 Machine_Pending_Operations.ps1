# Start of Settings
# End of Settings

$Title          = 'Machine Pending Operations'
$Header         = '[count] machine(s) with operation_state stuck'
$Comments       = "Provisioning operations stuck in 'CUSTOMIZING' or 'STARTING' over 30m indicate a hung agent or vCenter."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '50 Machines'
$Severity       = 'P2'
$Recommendation = 'Reset the affected VM (Horizon Console -> Reset). If chronic, drain pool and repush.'

if (-not (Get-HVRestSession)) { return }
$m = Get-HVMachine
if (-not $m) { return }
$stuck = @('CUSTOMIZING','STARTING','PROVISIONING','DELETING')
foreach ($x in $m) {
    if ($x.operation_state -in $stuck) {
        [pscustomobject]@{ Machine=$x.name; OperationState=$x.operation_state; Pool=$x.desktop_pool_name }
    }
}
