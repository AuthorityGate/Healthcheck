# Start of Settings
# Recommended PSP. Most modern arrays prefer Round Robin; 3PAR/HPE/Dell/Pure ship a SATP claim rule for it.
$RecommendedPolicy = 'RoundRobin'
# End of Settings

$Title          = "LUN Multipathing Policy"
$Header         = "[count] LUN(s) not on '$RecommendedPolicy'"
$Comments       = "VMware KB 1011340 / 2069356: SAN LUNs should use Round Robin (default for most arrays since vSphere 6.5) for active/active load balancing. 'Fixed' on a multi-path SAN under-utilizes paths; 'MRU' is acceptable only for active-passive arrays."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P3"
$Recommendation = "esxcli storage nmp device set --device <eui> --psp VMW_PSP_RR. Verify your storage vendor publishes a SATP claim rule and apply it via host profile."

if (-not $Global:VCConnected) { return }

Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    Get-ScsiLun -VmHost $h -LunType disk -ErrorAction SilentlyContinue | Where-Object {
        $_.MultipathPolicy -ne $RecommendedPolicy -and $_.MultipathPolicy -ne 'Unknown' -and $_.CanonicalName -notmatch '^mpx\.|^vsan'
    } | ForEach-Object {
        [pscustomobject]@{
            Host    = $h.Name
            LUN     = $_.CanonicalName
            Vendor  = $_.Vendor
            Model   = $_.Model
            Policy  = $_.MultipathPolicy
            Recommended = $RecommendedPolicy
        }
    }
}

$TableFormat = @{ Policy = { param($v,$row) 'warn' } }
