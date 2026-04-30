# Start of Settings
# End of Settings

$Title          = "View Composer Deprecation Notice"
$Header         = "[count] vCenter(s) still configured with View Composer (deprecated)"
$Comments       = "View Composer (linked clones) was deprecated in Horizon 8 2106 and removed in Horizon 8 2303. Pods still using Composer cannot upgrade past 2212 LTSR. Reference: 'Horizon 8 2303 Release Notes' / KB 88016."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "10 Connection Servers"
$Severity       = "P2"
$Recommendation = "Plan migration of every linked-clone pool to instant clones. Tooling: Horizon Migration Tool (Fling) or manual recompose to a Full Clone, then publish as IC."

if (-not (Get-HVRestSession)) { return }
$vc = Get-HVVirtualCenter
if (-not $vc) { return }

foreach ($v in $vc) {
    $hasComposer = $false
    if ($v.PSObject.Properties['view_composer_data']) { $hasComposer = [bool]$v.view_composer_data }
    if ($v.PSObject.Properties['composer_servers'])    { $hasComposer = $hasComposer -or ($v.composer_servers -and @($v.composer_servers).Count -gt 0) }
    if ($hasComposer) {
        [pscustomobject]@{
            vCenter        = $v.name
            ServerName     = $v.server_name
            ComposerActive = $true
            Note           = 'Plan removal before upgrading to Horizon 8 2303+'
        }
    }
}

$TableFormat = @{ ComposerActive = { param($v,$row) 'warn' } }
