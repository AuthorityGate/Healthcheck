# Start of Settings
# End of Settings

$Title          = 'Cluster vLCM Image Profile'
$Header         = 'Per-cluster vLCM image profile + add-ons'
$Comments       = 'vLCM image-mode clusters: base ESXi version, vendor add-on (Dell DSU / HPE Bundle / Lenovo OpenManage), components, and last-applied image.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'Info'
$Recommendation = 'Image-mode is the future of patching. Migrate baseline-managed clusters to image-managed.'

if (-not $Global:VCConnected) { return }
Get-Cluster -ErrorAction SilentlyContinue | ForEach-Object {
    $cl = $_
    $img = $cl.ExtensionData.ConfigurationEx.DesiredSoftwareSpec
    if ($img) {
        [pscustomobject]@{
            Cluster        = $cl.Name
            BaseImage      = $img.BaseImageSpec.Version
            VendorAddOn    = if ($img.VendorAddOnSpec) { $img.VendorAddOnSpec.Name + ' ' + $img.VendorAddOnSpec.Version } else { 'none' }
            ComponentCount = if ($img.ComponentSpec) { @($img.ComponentSpec).Count } else { 0 }
        }
    }
}
