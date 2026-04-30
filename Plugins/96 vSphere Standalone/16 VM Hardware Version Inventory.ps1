# Start of Settings
# Cohorts at or below this version will be flagged.
$MinHardwareVersion = 14
# End of Settings

$Title          = "Inventory-Wide VM Hardware Version Drift"
$Header         = "VM hardware version distribution (cohorts <= vmx-$MinHardwareVersion are flagged)"
$Comments       = "VMware KB 1010675: VM hardware versions older than the host's max prevent newer features (vMotion across CPU generations, vTPM, secure boot, RSSv2). vmx-9 is unsupported; vmx-11 missing many features."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P3"
$Recommendation = "Schedule a power-off + 'Upgrade VM Compatibility' rolling pass. For VDI parents see plugin 03 in '97 vSphere for Horizon'."

if (-not $Global:VCConnected) { return }

Get-VM -ErrorAction SilentlyContinue | Group-Object HardwareVersion | Sort-Object @{Expression={[int]($_.Name -replace '[^0-9]','')};Descending=$false} | ForEach-Object {
    $hv = [int]($_.Name -replace '[^0-9]','')
    [pscustomobject]@{
        HardwareVersion = $_.Name
        VMCount         = $_.Count
        BelowThreshold  = ($hv -le $MinHardwareVersion)
        Sample          = ($_.Group | Select-Object -First 1).Name
    }
}

$TableFormat = @{
    BelowThreshold = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
}
