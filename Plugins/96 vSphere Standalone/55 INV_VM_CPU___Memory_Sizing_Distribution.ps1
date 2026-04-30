# Start of Settings
# End of Settings

$Title          = 'VM CPU / Memory Sizing Distribution'
$Header         = 'Inventory-wide vCPU + RAM histogram'
$Comments       = 'Most-common vCPU and RAM allocations. Outliers (1 vCPU, 0.5 GB) often indicate forgotten test VMs.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'Info'
$Recommendation = 'Capacity-plan trend on vCPU/RAM allocation distribution.'

if (-not $Global:VCConnected) { return }
Get-VM -ErrorAction SilentlyContinue | Group-Object @{e={"$($_.NumCpu) vCPU / $($_.MemoryGB) GB"}} |
    Sort-Object Count -Descending | Select-Object -First 30 | ForEach-Object {
    [pscustomobject]@{ Sizing = $_.Name; Count = $_.Count }
}
