# Start of Settings
$ScanTimeoutSeconds = 60
# End of Settings

$Title          = 'RDSH Master Image Deep Scan'
$Header         = "[count] anti-pattern(s) across RDSH farm master images"
$Comments       = "Comprehensive introspection of every parent VM referenced by an RDSH farm. Same Tier 1 (vCenter) + Tier 2 (in-guest WinRM) pattern as the desktop deep-scan, but the rule set differs: RDSH masters are sized larger, expect RDP enabled, expect higher RAM, and have role-specific config (Remote Desktop Session Host role + RD Connection Broker integration). Each anti-pattern surfaces as one named-machine row."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '40 RDS Farms'
$Severity       = 'P2'
$Recommendation = "Apply each row's Fix on the master, generalize, re-snapshot, recompose all dependent farms. RDSH is more sensitive to image drift than desktop pools because session density amplifies any per-instance issue."

if (-not $Global:VCConnected -or -not (Get-HVRestSession)) { return }

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) -ChildPath '..\Modules\GuestImageScan.psm1'
if (-not (Test-Path $modulePath)) {
    [pscustomobject]@{ Machine='(plugin error)'; Rule='GuestImageScan.psm1 not found'; Detail="Expected at $modulePath"; Fix='Reinstall HealthCheckPS1.' }
    return
}
Import-Module $modulePath -Force

# Discover RDSH farm master VMs.
$masters = New-Object System.Collections.Generic.HashSet[string]
foreach ($f in (Get-HVFarm)) {
    foreach ($prop in 'automated_farm_settings','provisioning_settings','instant_clone_engine_provisioning_settings') {
        $s = $f.$prop
        if ($s -and $s.parent_vm_path) {
            [void]$masters.Add(($s.parent_vm_path -split '/')[-1])
        }
        # Some Horizon REST shapes nest provisioning under automated_farm_settings.provisioning_settings
        if ($s -and $s.provisioning_settings -and $s.provisioning_settings.parent_vm_path) {
            [void]$masters.Add(($s.provisioning_settings.parent_vm_path -split '/')[-1])
        }
    }
}
if ($masters.Count -eq 0) { return }

$cred = if (Test-Path Variable:Global:HVImageScanCredential) { $Global:HVImageScanCredential } else { $null }

foreach ($n in $masters) {
    $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
    if (-not $vm) {
        [pscustomobject]@{ Machine=$n; Role='RdshMaster'; Severity='P2'; Rule='RDSH master VM not found in vCenter'; Detail="Farm references master '$n' but vCenter does not see it."; Fix='Verify VM still exists; update farm or restore VM.' }
        continue
    }
    $scan = Get-GuestImageScan -Vm $vm -Role 'RdshMaster' -Credential $cred -WinRmTimeoutSeconds $ScanTimeoutSeconds

    [pscustomobject]@{
        Machine  = $vm.Name
        Role     = 'RdshMaster'
        Severity = 'Info'
        Rule     = "Scanned at $($scan.Tier)"
        Detail   = "vCPU=$($scan.VmHardware.vCpu) RAM=$($scan.VmHardware.RamGB)GB OS='$($scan.VmHardware.GuestOS)' HW=$($scan.VmHardware.HardwareVer) IP=$($scan.VmHardware.IPAddress)"
        Fix      = if ($scan.Tier -eq 'Tier1') { 'Supply PSCredential via $Global:HVImageScanCredential and verify WinRM reachable for Tier 2.' } else { 'No action - inventory only.' }
    }
    foreach ($f in $scan.Findings) { $f }
}

$TableFormat = @{
    Severity = { param($v,$row) if ($v -eq 'P1') { 'bad' } elseif ($v -eq 'P2') { 'warn' } else { '' } }
}
