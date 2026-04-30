# Start of Settings
# End of Settings

$Title          = 'vSAN Performance Service'
$Header         = '[count] cluster(s) with performance service disabled'
$Comments       = 'Performance service collects historical metrics. Disabled = no Skyline / capacity trending.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'P3'
$Recommendation = 'Cluster -> Configure -> vSAN -> Services -> Performance Service -> Enable.'

if (-not $Global:VCConnected) { return }
Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.VsanEnabled } | ForEach-Object {
    $p = $_.ExtensionData.ConfigurationEx.VsanConfigInfo.PerfsvcConfig
    if (-not $p -or -not $p.Enabled) {
        [pscustomobject]@{ Cluster=$_.Name; PerformanceService=$false }
    }
}
