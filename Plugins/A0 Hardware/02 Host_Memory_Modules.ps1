# Start of Settings
# End of Settings

$Title          = 'Host Memory Modules'
$Header         = 'Memory module population uniformity'
$Comments       = 'Asymmetric DIMM population on a multi-CPU host = unbalanced NUMA. Cluster-wide drift = noisy-neighbor potential.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'P3'
$Recommendation = 'Re-balance DIMMs across CPU sockets on the affected hosts.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $mem = $_.ExtensionData.Hardware.MemorySize
    [pscustomobject]@{
        Host        = $_.Name
        TotalMemGB  = [math]::Round($mem / 1GB, 1)
        Cluster     = $_.Parent.Name
        Sockets     = $_.ExtensionData.Hardware.CpuInfo.NumCpuPackages
    }
}
