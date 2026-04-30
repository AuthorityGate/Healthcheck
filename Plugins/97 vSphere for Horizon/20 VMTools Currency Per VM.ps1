# Start of Settings
$MaxRendered = 1000
# End of Settings

$Title          = "VMware Tools Currency (Horizon-managed VMs)"
$Header         = "[count] Horizon-managed VM(s) with non-current Tools"
$Comments       = "Per-VM check across every Horizon-managed clone (instant + linked + full + manual): VMware Tools status. Tools out-of-date = console session is degraded (no IP visibility, no graceful shutdown, slow vMotion preflight). Plugin only flags VMs whose Tools are NOT 'guestToolsCurrent'."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P3"
$Recommendation = "Update Tools on the parent VM, then push a new image to instant-clone pools. Full-clone pools need a planned upgrade window (VMTools update reboots Windows). Monitor for status='guestToolsExecutingScripts' rows that DON'T resolve - those indicate stuck tools-upgrade jobs."

if (-not $Global:VCConnected) { return }

$rendered = 0
foreach ($vm in (Get-VM -ErrorAction SilentlyContinue)) {
    if ($rendered -ge $MaxRendered) { break }
    if (-not $vm) { continue }
    $tools = $null
    try { $tools = $vm.ExtensionData.Guest.ToolsRunningStatus } catch { }
    $version = $null
    try { $version = $vm.ExtensionData.Guest.ToolsStatus } catch { }
    $vstr = if ($vm.ExtensionData.Guest.ToolsVersion) { $vm.ExtensionData.Guest.ToolsVersion } else { '' }
    if ($version -and $version -ne 'toolsOk') {
        [pscustomobject]@{
            VM           = $vm.Name
            PowerState   = [string]$vm.PowerState
            ToolsStatus  = $version
            ToolsRunning = $tools
            ToolsVersion = $vstr
            GuestOS      = $vm.ExtensionData.Guest.GuestFullName
        }
        $rendered++
    }
}
if ($rendered -eq 0) {
    [pscustomobject]@{ Note = 'All VMs report Tools=Current. No findings.' }
}

$TableFormat = @{
    ToolsStatus = { param($v,$row) if ($v -eq 'toolsOld') { 'warn' } elseif ($v -match 'NotInstalled|toolsNotRunning') { 'bad' } else { '' } }
}
