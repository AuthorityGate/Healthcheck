# Start of Settings
# End of Settings

$Title          = 'DEM Agent Version'
$Header         = 'DEM agent version reported by local install'
$Comments       = 'Verify DEM Agent matches the deployed Manager version. Mixed-version installs cause profile corruption.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P3'
$Recommendation = 'Update DEM Agent on the master VM and re-publish.'

try {
    $agent = Get-CimInstance -ClassName Win32_Product -Filter "Name LIKE '%VMware Dynamic Environment Manager%'" -ErrorAction SilentlyContinue |
              Select-Object -First 1
    if (-not $agent) { $agent = Get-CimInstance -ClassName Win32_Product -Filter "Name LIKE '%Dynamic Environment Manager Agent%'" -ErrorAction SilentlyContinue | Select-Object -First 1 }
} catch { }
if (-not $agent) { return }
[pscustomobject]@{
    Product   = $agent.Name
    Version   = $agent.Version
    Vendor    = $agent.Vendor
    Installed = $agent.InstallDate
}
