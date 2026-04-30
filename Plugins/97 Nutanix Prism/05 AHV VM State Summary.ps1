# Start of Settings
# End of Settings

$Title          = "AHV VM State Summary"
$Header         = "VM count grouped by power state, hypervisor, and cluster"
$Comments       = "Population view of every VM Prism can see. Equivalent of vSphere Inventory Counts but at VM granularity. Quickly answers 'how many VMs are running where, on which hypervisor, and how many are powered off / suspended'."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "Info"
$Recommendation = "Long-tail of OFF VMs accumulating on production clusters = housekeeping debt; archive or move to a non-prod container. Suspended VMs hold memory pages indefinitely - reset or power down."

if (-not (Get-NTNXRestSession)) { return }
$vms = @(Get-NTNXVM)
if (-not $vms) {
    [pscustomobject]@{ Note='No VMs visible to this account.' }
    return
}

# Two-dimensional summary: cluster x power_state.
$grouped = $vms | Group-Object -Property @{Expression={ if ($_.cluster_reference) { $_.cluster_reference.name } else { '(unknown)' } }}, power_state |
    ForEach-Object {
        $cl, $ps = $_.Name -split ', ', 2
        [pscustomobject]@{
            Cluster    = $cl
            PowerState = if ($ps) { $ps } else { '(unknown)' }
            VMCount    = $_.Count
            TotalvCPU  = ($_.Group | Measure-Object -Property num_vcpus_per_socket -Sum).Sum
            TotalMemGB = [math]::Round((($_.Group | Measure-Object -Property memory_size_mib -Sum).Sum / 1024), 0)
        }
    }
$grouped | Sort-Object Cluster, PowerState

$TableFormat = @{
    PowerState = { param($v,$row) if ($v -eq 'ON') { 'ok' } elseif ($v -in @('OFF','SUSPENDED','PAUSED')) { 'warn' } elseif ($v) { 'bad' } else { '' } }
}
