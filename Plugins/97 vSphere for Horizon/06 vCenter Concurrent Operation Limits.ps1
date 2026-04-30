# Start of Settings
# Per Horizon Architecture Planning, the vCenter that backs a Horizon pod should
# permit at least these concurrencies for instant clone / power / maintenance.
$MinPower        = 50
$MinProvisioning = 20
$MinMaintenance  = 12
# End of Settings

$Title          = "vCenter Concurrent Operation Limits"
$Header         = "vCenter concurrent op limits compared to Horizon recommendations"
$Comments       = "Reference: 'Horizon Architecture Planning - Concurrent Operations on a vCenter Server' (Horizon docs). Limits set too low throttle login storms / refresh; too high can overload smaller vCenters."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P3"
$Recommendation = "Horizon Console -> Settings -> Servers -> vCenter Servers -> Edit -> Advanced. Raise to 50 / 20 / 12 (or higher for IC pools at scale)."

if (-not (Get-HVRestSession)) { return }
$vc = Get-HVVirtualCenter
if (-not $vc) { return }

foreach ($v in $vc) {
    $l   = $v.limits
    $pwr = if ($l) { $l.max_concurrent_power_operations } else { $null }
    $prv = if ($l) { $l.max_concurrent_provisioning_operations } else { $null }
    $mnt = if ($l) { $l.max_concurrent_maintenance_operations } else { $null }
    $bad = ($pwr -lt $MinPower) -or ($prv -lt $MinProvisioning) -or ($mnt -lt $MinMaintenance)
    [pscustomobject]@{
        vCenter           = $v.name
        PowerOps          = "$pwr (min $MinPower)"
        ProvisioningOps   = "$prv (min $MinProvisioning)"
        MaintenanceOps    = "$mnt (min $MinMaintenance)"
        Verdict           = if ($bad) { 'Below recommendation' } else { 'OK' }
    }
}

$TableFormat = @{
    Verdict = { param($v,$row) if ($v -ne 'OK') { 'warn' } else { 'ok' } }
}
