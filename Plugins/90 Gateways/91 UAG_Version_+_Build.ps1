# Start of Settings
# End of Settings

$Title          = 'UAG Version + Build'
$Header         = 'Connected UAG version / build'
$Comments       = 'Reference: UAG release-notes / VMSA bulletins. UAGs not on the latest LTSR accumulate Blast/PCoIP CVEs.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '90 Gateways'
$Severity       = 'P2'
$Recommendation = 'Plan UAG upgrade quarterly. Use a side-by-side blue/green swap behind the load balancer.'

if (-not (Get-UAGRestSession)) { return }
$v = Get-UAGVersion
if (-not $v) { return }
[pscustomobject]@{
    Version    = $v.version
    Build      = $v.build_number
    Branch     = $v.branch
    OsVersion  = $v.osVersion
}
