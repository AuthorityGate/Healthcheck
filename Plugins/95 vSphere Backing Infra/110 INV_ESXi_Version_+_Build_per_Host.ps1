# Start of Settings
# End of Settings

$Title          = 'ESXi Version + Build per Host'
$Header         = 'Per-host ESXi version + build + image profile + last update'
$Comments       = 'Specific version / build / image profile per host. Drift indicates incomplete vLCM rollout. Build numbers map to KB 2143832 for security currency.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'Info'
$Recommendation = 'Run vLCM remediation when build drift is detected.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    $boot = $h.ExtensionData.Summary.Runtime.BootTime
    $age = if ($boot) { [int](([DateTime]::Now - $boot).TotalDays) } else { -1 }
    [pscustomobject]@{
        Host        = $h.Name
        Version     = $h.Version
        Build       = $h.Build
        ApiVersion  = $h.ApiVersion
        ImageProfile = $h.ExtensionData.Config.Product.LicenseProductName
        BootTime    = $boot
        UptimeDays  = $age
        Cluster     = $h.Parent.Name
    }
}
