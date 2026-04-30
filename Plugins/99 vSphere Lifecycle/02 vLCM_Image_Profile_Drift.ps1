# Start of Settings
# End of Settings

$Title          = 'vLCM Image Profile Drift'
$Header         = 'Image-vs-running compliance'
$Comments       = 'Hosts running an image other than the cluster image are non-compliant.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P2'
$Recommendation = "Cluster -> Updates -> Image -> 'Check Compliance' then 'Remediate'."

if (-not $Global:VCConnected) { return }
[pscustomobject]@{
    Note = 'PowerCLI cmdlet Get-VMHostImageProfileCompliance is deprecated; verify via vSphere Client -> Updates -> Image.'
    Reference = 'vSphere Lifecycle Manager Admin Guide'
}
