# Start of Settings
# End of Settings

$Title          = "VMware Tools Currency"
$Header         = "[count] VM(s) with VMware Tools out of date or not running"
$Comments       = "VMware KB 1014294 / 2073753: out-of-date Tools cause guest customization errors, snapshot quiescing failures, and broken time-sync. Status 'guestToolsNotInstalled' is also a finding for production VMs."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P3"
$Recommendation = "Use vSphere Lifecycle Manager (vLCM) or push manually via 'Install/Upgrade VMware Tools'. For Windows: silent ZIP install with /S /v 'reboot=R'."

if (-not $Global:VCConnected) { return }

Get-VM -ErrorAction SilentlyContinue | ForEach-Object {
    $vm = $_
    $tv = $vm.ExtensionData.Guest.ToolsVersionStatus2
    $tr = $vm.ExtensionData.Guest.ToolsRunningStatus
    $bad = $tv -in 'guestToolsNeedUpgrade','guestToolsTooOld','guestToolsUnmanaged','guestToolsNotInstalled' `
            -or $tr -eq 'guestToolsNotRunning'
    if ($bad) {
        [pscustomobject]@{
            VM            = $vm.Name
            PowerState    = $vm.PowerState
            ToolsStatus   = $tv
            ToolsRunning  = $tr
            ToolsVersion  = $vm.ExtensionData.Guest.ToolsVersion
            Guest         = $vm.Guest.OSFullName
        }
    }
}

$TableFormat = @{
    ToolsStatus  = { param($v,$row) if ($v -eq 'guestToolsNotInstalled') { 'bad' } else { 'warn' } }
    ToolsRunning = { param($v,$row) if ($v -eq 'guestToolsNotRunning' -and $row.PowerState -eq 'PoweredOn') { 'bad' } else { '' } }
}
