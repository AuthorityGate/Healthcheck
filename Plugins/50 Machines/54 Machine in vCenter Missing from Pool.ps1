# Start of Settings
# End of Settings

$Title          = 'Machines in vCenter but Missing from Horizon'
$Header         = '[count] VM(s) under the Horizon vCenter folder not registered with Horizon'
$Comments       = 'Common artefact of failed cloning / aborted recompose. Wastes datastore + AD machine accounts.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '50 Machines'
$Severity       = 'P3'
$Recommendation = "Decide: re-register (rare) or delete the orphans. Verify they aren't lingering AD accounts as well."

if (-not $Global:VCConnected -or -not (Get-HVRestSession)) { return }
$pools = Get-HVDesktopPool
if (-not $pools) { return }
$horizonNames = @{}
foreach ($m in (Get-HVMachine)) { $horizonNames[$m.name] = $true }
$folders = New-Object System.Collections.Generic.HashSet[string]
foreach ($p in $pools) {
    foreach ($prop in 'provisioning_settings','instant_clone_engine_provisioning_settings') {
        if ($p.$prop -and $p.$prop.vm_folder_path) { [void]$folders.Add(($p.$prop.vm_folder_path -split '/')[-1]) }
    }
}
foreach ($f in $folders) {
    $folder = Get-Folder -Name $f -ErrorAction SilentlyContinue
    if (-not $folder) { continue }
    foreach ($vm in (Get-VM -Location $folder -ErrorAction SilentlyContinue)) {
        if (-not $horizonNames.ContainsKey($vm.Name)) {
            [pscustomobject]@{ VM=$vm.Name; Folder=$f; PowerState=$vm.PowerState }
        }
    }
}

