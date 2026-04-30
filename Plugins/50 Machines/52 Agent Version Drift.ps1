# Start of Settings
# Show only the bottom N most-out-of-date cohorts (0 = show all).
$ShowOnlyOldest = 0
# End of Settings

$Title          = "Horizon Agent Version Drift"
$Header         = "Distinct Horizon Agent versions in the deployment"
$Comments       = "Multiple agent versions running in production is normal during a rollout. A drift of more than two minor versions usually indicates a stalled image-update cycle."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "50 Machines"
$Severity       = "P3"
$Recommendation = "Update parent VMs to the current Horizon Agent and re-push to all affected pools."

$m = Get-HVMachine
if (-not $m) { return }

$cohorts = $m | Where-Object { $_.agent_version } |
    Group-Object agent_version |
    Sort-Object @{Expression={[version]($_.Name -replace '[^0-9.]','')};Descending=$true} -ErrorAction SilentlyContinue

if ($ShowOnlyOldest -gt 0) {
    $cohorts = $cohorts | Select-Object -Last $ShowOnlyOldest
}

$cohorts | ForEach-Object {
    [pscustomobject]@{
        AgentVersion = $_.Name
        MachineCount = $_.Count
        SamplePool   = ($_.Group | Select-Object -First 1).desktop_pool_name
    }
}
