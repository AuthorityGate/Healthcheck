# Start of Settings
# End of Settings

$Title          = 'vCenter VM-Host Affinity Groups'
$Header         = '[count] DRS VM-Host group(s)'
$Comments       = 'DRS Groups underpin VM-to-Host rules (license enforcement, blade-level pinning).'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'Info'
$Recommendation = 'Confirm groups match licensing constraints (Microsoft + Oracle host pinning).'

if (-not $Global:VCConnected) { return }
Get-DrsClusterGroup -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{ Cluster=$_.Cluster.Name; Group=$_.Name; Type=$_.GroupType; MemberCount=@($_.Member).Count }
}
