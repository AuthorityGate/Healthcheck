# Start of Settings
# End of Settings

$Title          = 'VMs with thin-disk consumption > 90%'
$Header         = '[count] thin-disk VM(s) above 90% provisioned'
$Comments       = 'Thin disks fill silently; an over-provisioned datastore can wedge production.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P2'
$Recommendation = 'Storage vMotion to another datastore, expand the VMDK, or convert to thick on a healthier datastore.'

if (-not $Global:VCConnected) { return }
Get-VM -ErrorAction SilentlyContinue | ForEach-Object {
    $vm = $_
    foreach ($d in (Get-HardDisk -VM $vm -ErrorAction SilentlyContinue)) {
        if ($d.StorageFormat -eq 'Thin' -and $d.CapacityGB -gt 0) {
            $usedGB = if ($vm.UsedSpaceGB -and $vm.ProvisionedSpaceGB -gt 0) { $vm.UsedSpaceGB } else { 0 }
            $pct = [math]::Round(($usedGB / $vm.ProvisionedSpaceGB) * 100, 1)
            if ($pct -gt 90) {
                [pscustomobject]@{ VM=$vm.Name; ProvisionedGB=[math]::Round($vm.ProvisionedSpaceGB,1); UsedGB=[math]::Round($usedGB,1); UsedPct=$pct }
                break
            }
        }
    }
}
