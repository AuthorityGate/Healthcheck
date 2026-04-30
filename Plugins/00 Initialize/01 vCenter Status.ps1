# Start of Settings
# End of Settings

$Title          = "vCenter Enrichment"
$Header         = "vSphere PowerCLI session"
$Comments       = "Reports whether vCenter enrichment is available for vSphere-backed plugins."
$Display        = "List"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "00 Initialize"
$Severity       = "Info"

if ($Global:VCConnected) {
    $vi = $global:DefaultVIServer
    [pscustomobject]@{
        'vCenter'  = if ($vi) { $vi.Name } else { '(unknown)' }
        'Version'  = if ($vi) { $vi.Version } else { '' }
        'Build'    = if ($vi) { $vi.Build } else { '' }
        'User'     = if ($vi) { $vi.User } else { '' }
    }
} else {
    [pscustomobject]@{
        'vCenter'  = '(not connected)'
        'Note'     = 'vSphere-backing-infra plugins will skip. Pass -VCServer or set $VCServer.'
    }
}
