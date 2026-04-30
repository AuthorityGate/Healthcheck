# Start of Settings
# End of Settings

$Title          = 'VMs with Disconnected vNICs'
$Header         = '[count] VM(s) with at least one disconnected vNIC'
$Comments       = 'Common artefact of decommissioned VLANs / dangling networks. VMs lose connectivity silently.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Reconnect or remove the disconnected adapter.'

if (-not $Global:VCConnected) { return }
Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.PowerState -eq 'PoweredOn' } | ForEach-Object {
    $vm = $_
    $bad = Get-NetworkAdapter -VM $vm -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionState.Connected -eq $false }
    if ($bad) {
        [pscustomobject]@{ VM=$vm.Name; DisconnectedNICs=@($bad).Count }
    }
}
