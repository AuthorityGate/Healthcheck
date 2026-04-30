# Start of Settings
$MaxRendered = 500
# End of Settings

$Title          = "VM Hardware Version Drift"
$Header         = "Distribution of VM hardware versions in this vCenter inventory"
$Comments       = "Per-VM hardware version (compatibility level). Mixed hardware versions are normal during rolling upgrades but should converge over time. Older versions (< vmx-15 / ESXi 7) limit modern features (vGPU profiles, DirectPath, larger memory)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "Info"
$Recommendation = "vmx-15 = ESXi 7.0 baseline. vmx-19 = ESXi 7.0 U2+. vmx-21 = ESXi 8.0+. Plan vmx upgrades alongside ESXi upgrades; the upgrade requires a power-cycle. For Horizon parent VMs, schedule the bump on the parent then re-push to children."

if (-not $Global:VCConnected) { return }

$counts = @{}
foreach ($vm in (Get-VM -ErrorAction SilentlyContinue)) {
    if (-not $vm) { continue }
    $hw = if ($vm.HardwareVersion) { $vm.HardwareVersion } else { '(unknown)' }
    if (-not $counts.ContainsKey($hw)) { $counts[$hw] = 0 }
    $counts[$hw]++
}
foreach ($k in ($counts.Keys | Sort-Object)) {
    [pscustomobject]@{
        HardwareVersion = $k
        VMCount         = $counts[$k]
        ESXiBaseline    = switch -Wildcard ($k) {
            'vmx-21' { 'ESXi 8.0+' }
            'vmx-20' { 'ESXi 7.0 U3+' }
            'vmx-19' { 'ESXi 7.0 U2+' }
            'vmx-18' { 'ESXi 7.0 U1+' }
            'vmx-17' { 'ESXi 7.0' }
            'vmx-15' { 'ESXi 6.7' }
            'vmx-14' { 'ESXi 6.7 (older)' }
            'vmx-13' { 'ESXi 6.5' }
            'vmx-11' { 'ESXi 6.0' }
            default  { 'unknown / pre-6.0' }
        }
    }
}

$TableFormat = @{
    ESXiBaseline = { param($v,$row) if ($v -match '8\.0') { 'ok' } elseif ($v -match '7\.0') { 'ok' } elseif ($v -match '6\.5|6\.7') { 'warn' } elseif ($v -match '6\.0|pre') { 'bad' } else { '' } }
}
