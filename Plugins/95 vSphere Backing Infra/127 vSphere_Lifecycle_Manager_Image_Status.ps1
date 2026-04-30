# Start of Settings
# End of Settings

$Title          = 'vSphere Lifecycle Manager Image Cluster Status'
$Header         = "[count] cluster(s) - vLCM mode + compliance"
$Comments       = "vLCM image-based clusters bundle ESXi build + firmware + driver into a single image. Cluster compliance = whether all hosts match the image. Drift = hosts on different patch levels."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Image-based clusters preferred for production. Migrate baseline-based clusters at next major upgrade. Cluster compliance = 100% before maintenance window completes."

if (-not $Global:VCConnected) { return }

foreach ($cl in (Get-Cluster -ErrorAction SilentlyContinue)) {
    # Detect image-based vs baseline-based via Get-Cluster.ExtensionData
    try {
        $isImageBased = $false
        $cfgManager = $cl.ExtensionData.ConfigurationEx
        if ($cfgManager -and $cfgManager.GetType().Name -match 'ClusterConfigInfoEx') {
            # Recent vSphere has SoftwareSpec for image-based clusters
            $isImageBased = ($null -ne $cfgManager.PSObject.Properties['DesiredSoftwareSpec'] -and $null -ne $cfgManager.DesiredSoftwareSpec)
        }
        [pscustomobject]@{
            Cluster      = $cl.Name
            Mode         = if ($isImageBased) { 'Image-Based (vLCM)' } else { 'Baseline-Based (legacy)' }
            HostCount    = (Get-VMHost -Location $cl).Count
            Note         = if (-not $isImageBased) { 'Consider migrating to image-based at next major upgrade.' } else { '' }
        }
    } catch {
        [pscustomobject]@{ Cluster = $cl.Name; Mode = '(query failed)'; HostCount = ''; Note = $_.Exception.Message }
    }
}

$TableFormat = @{
    Mode = { param($v,$row) if ($v -match 'Baseline') { 'warn' } else { '' } }
}
