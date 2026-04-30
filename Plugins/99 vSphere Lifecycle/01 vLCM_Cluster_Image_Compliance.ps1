# Start of Settings
# End of Settings

$Title          = 'vLCM Cluster Image Compliance'
$Header         = '[count] cluster(s) using vLCM Image baselines'
$Comments       = "Reference: 'vSphere Lifecycle Manager' (VMware docs). vLCM image-mode is the future of patching."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'Info'
$Recommendation = 'Migrate baseline-managed clusters to image-managed.'

if (-not $Global:VCConnected) { return }
Get-Cluster -ErrorAction SilentlyContinue | ForEach-Object {
    $img = $_.ExtensionData.ConfigurationEx.DesiredSoftwareSpec
    [pscustomobject]@{
        Cluster      = $_.Name
        ImageMode    = if ($img) { $true } else { $false }
        Baseline     = if ($img) { $img.BaseImageSpec.Version } else { '(baseline mode)' }
    }
}
