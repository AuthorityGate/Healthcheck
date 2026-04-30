# Start of Settings
# Heuristic: VDI workloads rarely need > 8 vCPU + 32 GB RAM. Beyond that
# is usually a DBA / engineering / dev VM that wandered into the cluster.
$VCPULimit = 8
$MemGBLimit = 32
$MaxRendered = 500
# End of Settings

$Title          = "Oversized VM Detection"
$Header         = "[count] VM(s) sized beyond typical VDI workload"
$Comments       = "VMs with vCPU > $VCPULimit OR memory > $MemGBLimit GB. These are usually misclassified server / engineering workloads that ended up on the VDI cluster, OR genuinely heavy power-users that should be on dedicated tier-2 capacity. Either way they consume disproportionate share of cluster CPU + RAM that the planning model didn't account for."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P3"
$Recommendation = "Move oversized non-VDI workload to a server cluster. For genuinely heavy VDI users, document them in a tier-2 power-user pool with explicit reservation - capacity-plan for that tier separately."

if (-not $Global:VCConnected) { return }

$rendered = 0
foreach ($vm in (Get-VM -ErrorAction SilentlyContinue)) {
    if (-not $vm) { continue }
    if ($rendered -ge $MaxRendered) { break }
    $cpu = [int]$vm.NumCpu
    $mem = [math]::Round($vm.MemoryGB, 1)
    if ($cpu -gt $VCPULimit -or $mem -gt $MemGBLimit) {
        [pscustomobject]@{
            VM           = $vm.Name
            vCPU         = $cpu
            MemoryGB     = $mem
            ResourcePool = if ($vm.ResourcePool) { $vm.ResourcePool.Name } else { '' }
            Folder       = if ($vm.Folder) { $vm.Folder.Name } else { '' }
            PowerState   = [string]$vm.PowerState
            HasReservation = [bool]($vm.ExtensionData.Config.MemoryReservationLockedToMax -or $vm.ExtensionData.ResourceConfig.MemoryAllocation.Reservation -gt 0)
        }
        $rendered++
    }
}
if ($rendered -eq 0) {
    [pscustomobject]@{ Note = "No VMs exceed the $VCPULimit vCPU / $MemGBLimit GB heuristic." }
}

$TableFormat = @{
    vCPU     = { param($v,$row) if ([int]"$v" -gt 16) { 'bad' } elseif ([int]"$v" -gt 8) { 'warn' } else { '' } }
    MemoryGB = { param($v,$row) if ([double]"$v" -gt 64) { 'bad' } elseif ([double]"$v" -gt 32) { 'warn' } else { '' } }
}
