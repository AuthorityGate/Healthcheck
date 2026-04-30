# Start of Settings
# End of Settings

$Title          = 'Encrypted vMotion Setting per VM'
$Header         = '[count] VM(s) with Encrypted vMotion = Disabled'
$Comments       = "vSphere 6.5+ supports per-VM Encrypted vMotion: Disabled / Opportunistic (default) / Required. Required-mode encrypts the migration stream end-to-end. Best practice for tenant-isolated or regulated workloads is Required."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = "Per VM: VM -> Edit Settings -> VM Options -> Encryption -> 'Encrypted vMotion' = Required (or Opportunistic at minimum). Apply to regulated workloads first."

if (-not $Global:VCConnected) { return }

foreach ($vm in (Get-VM -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $mode = $vm.ExtensionData.Config.MigrateEncryption
        if ($mode -eq 'disabled') {
            [pscustomobject]@{
                VM       = $vm.Name
                Encrypt  = $mode
                Cluster  = if ($vm.VMHost -and $vm.VMHost.Parent) { $vm.VMHost.Parent.Name } else { '' }
                Note     = 'Migration stream NOT encrypted across vMotion network.'
            }
        }
    } catch { }
}

$TableFormat = @{
    Encrypt = { param($v,$row) if ($v -eq 'disabled') { 'warn' } else { '' } }
}
