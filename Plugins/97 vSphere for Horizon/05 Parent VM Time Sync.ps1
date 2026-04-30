# Start of Settings
# End of Settings

$Title          = "Horizon Parent VM 'Sync Time with Host' Setting"
$Header         = "[count] parent VM(s) syncing time from ESXi host"
$Comments       = "VMware KB 1189 + Horizon best practice: parent VMs (and the children they spawn) must NOT sync time from the host. Time should come from AD / NTP on the guest. Mixed sync sources cause Kerberos failures and 'Could not locate domain controller' brokering errors."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P2"
$Recommendation = "VM -> Edit Settings -> VM Options -> VMware Tools -> uncheck 'Synchronize time with host'. For Win11 + vTPM: also uncheck periodic sync (advanced)."

if (-not $Global:VCConnected) { return }

# Parent VM set: Horizon REST + manual picker list. Either alone is valid.
$parents = New-Object System.Collections.Generic.HashSet[string]
if (Get-HVRestSession) {
    foreach ($p in (Get-HVDesktopPool)) {
        foreach ($prop in 'provisioning_settings','instant_clone_engine_provisioning_settings') {
            $s = $p.$prop
            if ($s -and $s.parent_vm_path) { [void]$parents.Add(($s.parent_vm_path -split '/')[-1]) }
        }
    }
}
if (Test-Path Variable:Global:HVManualGoldImageList) {
    foreach ($n in @($Global:HVManualGoldImageList)) { if ($n) { [void]$parents.Add($n) } }
}
if ($parents.Count -eq 0) { return }

foreach ($n in $parents) {
    $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
    if (-not $vm) { continue }
    $opt = $vm.ExtensionData.Config.Tools
    if ($opt.SyncTimeWithHost) {
        [pscustomobject]@{
            ParentVM    = $vm.Name
            SyncWithHost = $true
            ToolsInstall = $opt.ToolsInstallType
            BeforeReady  = $opt.BeforeGuestReboot
        }
    }
}

$TableFormat = @{ SyncWithHost = { param($v,$row) 'warn' } }
