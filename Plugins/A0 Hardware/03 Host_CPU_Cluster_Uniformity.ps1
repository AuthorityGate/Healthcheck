# Start of Settings
# End of Settings

$Title          = 'Host CPU Cluster Uniformity'
$Header         = 'Different CPU SKUs in the same cluster'
$Comments       = 'Mixing CPUs within a cluster restricts EVC, can break vMotion.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'P2'
$Recommendation = 'Set EVC to the lowest-common baseline. Plan a refresh to homogenize SKUs.'

if (-not $Global:VCConnected) { return }
Get-Cluster -ErrorAction SilentlyContinue | ForEach-Object {
    $cl = $_
    $models = (Get-VMHost -Location $cl).ExtensionData.Hardware.CpuPkg | Select-Object -ExpandProperty Description -Unique
    if ($models.Count -gt 1) {
        [pscustomobject]@{ Cluster=$cl.Name; CpuSkus=$models -join ' | '; Models=$models.Count }
    }
}
