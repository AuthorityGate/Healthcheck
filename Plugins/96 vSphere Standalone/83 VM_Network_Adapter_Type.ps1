# Start of Settings
# End of Settings

$Title          = 'VM Network Adapter Type Inventory'
$Header         = '[count] VM(s) using legacy (E1000/E1000E/PCNet32) NICs'
$Comments       = "VMXNET3 is paravirtualized, supports up to 10/40 GbE in the guest, RSSv2, IPv6 TSO. E1000/E1000E are legacy emulated NICs; PCNet32 is ancient. Modern guests should be on VMXNET3 (requires VMware Tools)."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Per VM (powered off): Edit Settings -> Network Adapter -> Adapter Type = VMXNET3. Sysprep or driver re-install in the guest after the change (NIC swap resets IP config).'

if (-not $Global:VCConnected) { return }

foreach ($vm in (Get-VM -ErrorAction SilentlyContinue | Sort-Object Name)) {
    foreach ($n in (Get-NetworkAdapter -VM $vm -ErrorAction SilentlyContinue)) {
        if ($n.Type -ne 'Vmxnet3') {
            [pscustomobject]@{
                VM        = $vm.Name
                Cluster   = if ($vm.VMHost -and $vm.VMHost.Parent) { $vm.VMHost.Parent.Name } else { '' }
                Adapter   = $n.Name
                Type      = $n.Type
                Network   = $n.NetworkName
                MAC       = $n.MacAddress
            }
        }
    }
}

$TableFormat = @{
    Type = { param($v,$row) if ($v -match 'PCNet|E1000') { 'warn' } else { '' } }
}
