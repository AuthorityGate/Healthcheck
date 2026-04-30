# Start of Settings
# End of Settings

$Title          = 'Guest OS Distribution'
$Header         = 'Inventory-wide guest OS histogram'
$Comments       = 'Top-N guest operating systems across all VMs. Useful for license-counting (Windows Server, RHEL) and for OS-EOL planning.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'Info'
$Recommendation = 'Plan upgrades for any OS within 12 months of vendor EOL.'

if (-not $Global:VCConnected) { return }
Get-VM -ErrorAction SilentlyContinue | Group-Object @{e={$_.Guest.OSFullName}} |
    Sort-Object Count -Descending | Select-Object -First 30 | ForEach-Object {
    [pscustomobject]@{ GuestOS = $_.Name; Count = $_.Count }
}
