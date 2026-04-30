# Start of Settings
# End of Settings

$Title          = "VMs with Connected ISO / Floppy Media"
$Header         = "[count] VM(s) hold a CD/DVD ISO or floppy attachment"
$Comments       = "VMware KB 78809: A connected datastore-ISO blocks vMotion / DRS, breaks instant-clone push-image, and is the #1 cause of 'failed to find host' provisioning errors during desktop maintenance."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "95 vSphere Backing Infra"
$Severity       = "P2"
$Recommendation = "Detach via 'Edit Settings' -> CD/DVD -> 'Client Device' (or disconnect via PowerCLI: Get-CDDrive | Set-CDDrive -NoMedia)."

if (-not $Global:VCConnected) { return }

Get-VM -ErrorAction SilentlyContinue | ForEach-Object {
    $vm = $_
    $cd = Get-CDDrive -VM $vm -ErrorAction SilentlyContinue | Where-Object { $_.IsoPath -or $_.HostDevice }
    foreach ($d in $cd) {
        [pscustomobject]@{
            VM       = $vm.Name
            PowerOn  = $vm.PowerState
            Type     = 'CD/DVD'
            IsoPath  = $d.IsoPath
            HostDev  = $d.HostDevice
            Connected = $d.ConnectionState.Connected
        }
    }
    $fd = Get-FloppyDrive -VM $vm -ErrorAction SilentlyContinue | Where-Object { $_.FloppyImagePath }
    foreach ($d in $fd) {
        [pscustomobject]@{
            VM       = $vm.Name
            PowerOn  = $vm.PowerState
            Type     = 'Floppy'
            IsoPath  = $d.FloppyImagePath
            HostDev  = ''
            Connected = $d.ConnectionState.Connected
        }
    }
}
