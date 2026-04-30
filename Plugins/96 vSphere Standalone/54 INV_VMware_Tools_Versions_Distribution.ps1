# Start of Settings
# End of Settings

$Title          = 'VMware Tools Versions Distribution'
$Header         = 'Inventory-wide VMware Tools version histogram'
$Comments       = 'Tools versions across all powered-on VMs. Sub-12000 Tools versions are end-of-life on current vSphere.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'Info'
$Recommendation = "Patch via 'Upgrade VMware Tools' on a maintenance schedule."

if (-not $Global:VCConnected) { return }
Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.PowerState -eq 'PoweredOn' } |
    Group-Object @{e={$_.ExtensionData.Guest.ToolsVersion}} |
    Sort-Object Count -Descending | ForEach-Object {
    [pscustomobject]@{ ToolsVersion=$_.Name; Count=$_.Count }
}
