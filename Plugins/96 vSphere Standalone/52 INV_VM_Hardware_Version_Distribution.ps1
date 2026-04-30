# Start of Settings
# End of Settings

$Title          = 'VM Hardware Version Distribution'
$Header         = 'Inventory-wide VM hardware version histogram'
$Comments       = 'Distribution of vmx-* versions across all VMs. Anything below vmx-15 is missing modern features (vTPM, secure boot).'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'Info'
$Recommendation = "Plan a rolling 'Compatibility -> Upgrade VM Compatibility' across the inventory."

if (-not $Global:VCConnected) { return }
Get-VM -ErrorAction SilentlyContinue | Group-Object HardwareVersion |
    Sort-Object @{e={[int]($_.Name -replace '[^0-9]','')}} | ForEach-Object {
    [pscustomobject]@{ HardwareVersion=$_.Name; VMCount=$_.Count }
}
