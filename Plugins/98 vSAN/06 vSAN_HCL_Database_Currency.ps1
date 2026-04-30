# Start of Settings
# End of Settings

$Title          = 'vSAN HCL Database Currency'
$Header         = 'vSAN HCL DB age'
$Comments       = 'Old HCL DB hides incompatible NVMe / HBA / firmware. Refresh weekly for production.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'P2'
$Recommendation = 'Cluster -> Configure -> vSAN -> Update from File OR enable internet auto-refresh.'

if (-not $Global:VCConnected) { return }
[pscustomobject]@{
    Note = 'Enable internet auto-refresh in vSAN Skyline Health, or upload current HCL DB monthly.'
    Reference = 'KB 2114803 / Skyline Health -> HCL DB up-to-date'
}
