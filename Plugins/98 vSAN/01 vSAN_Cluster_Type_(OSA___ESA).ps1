# Start of Settings
# End of Settings

$Title          = 'vSAN Cluster Type (OSA / ESA)'
$Header         = 'Per-cluster vSAN architecture'
$Comments       = 'VMware vSAN comes in two architectures: OSA (Original) and ESA (Express). ESA needs flash-only NVMe.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'Info'
$Recommendation = 'Confirm cluster type matches the hardware. Upgrade OSA to ESA when refreshing hardware.'

if (-not $Global:VCConnected) { return }
Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.VsanEnabled } | ForEach-Object {
    $arch = if ($_.ExtensionData.ConfigurationEx -and $_.ExtensionData.ConfigurationEx.VsanConfigInfo.VsanEsaEnabled) { 'ESA' } else { 'OSA' }
    [pscustomobject]@{ Cluster=$_.Name; Architecture=$arch; HostCount=$_.ExtensionData.Host.Count }
}
