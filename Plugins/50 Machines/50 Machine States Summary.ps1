# Start of Settings
# End of Settings

$Title          = "Machine State Summary"
$Header         = "Distribution of machine states across all desktop pools"
$Comments       = "Per-state count of every Horizon-managed VM. Healthy: AVAILABLE / CONNECTED / CUSTOMIZING / PROVISIONING. Anything else needs attention."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "50 Machines"
$Severity       = "Info"

$m = @(Get-HVMachine)
if ($m.Count -eq 0) { return }

# Per-machine state lives under different field names depending on
# Horizon build + MP plugin (vSphere vs AHV). Try each in order and use
# the first non-empty value. Aggregator below groups by the resolved
# state so the State column never lands blank when the API returned data.
$resolved = foreach ($vm in $m) {
    $st = $null
    foreach ($k in @('machine_state','state','agent_state','operation_state','running_state','power_state','status')) {
        if ($vm.PSObject.Properties[$k] -and $vm.$k) { $st = [string]$vm.$k; break }
    }
    if (-not $st) { $st = '(unknown)' }
    [pscustomobject]@{ Machine = $vm.name; State = $st }
}

$resolved | Group-Object State | Sort-Object Count -Descending | ForEach-Object {
    [pscustomobject]@{
        State = $_.Name
        Count = $_.Count
        Healthy = $_.Name -in 'AVAILABLE','CONNECTED','DISCONNECTED','CUSTOMIZING','PROVISIONING','PROVISIONED','POWERED_ON','ON'
    }
}

$TableFormat = @{
    Healthy = { param($v,$row) if ($v -eq $false) { 'warn' } else { 'ok' } }
}
