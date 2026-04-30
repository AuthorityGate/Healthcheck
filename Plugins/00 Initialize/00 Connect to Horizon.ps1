# Start of Settings
# (none - handled in GlobalVariables.ps1)
# End of Settings

$Title          = "Horizon Connection"
$Header         = "Connected to Horizon Connection Server"
$Comments       = "Verifies the runner authenticated to the Horizon REST API."
$Display        = "List"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "00 Initialize"
$Severity       = "Info"

$s = Get-HVRestSession
if (-not $s) {
    [pscustomobject]@{
        'Connection Server' = '(not connected)'
        'Note'              = 'Horizon plugins will skip. Provide a Connection Server FQDN in the GUI or pass -Server.'
    }
    return
}

[pscustomobject]@{
    'Connection Server' = $s.Server
    'API Base URL'      = $s.BaseUrl
    'Connected At'      = $s.ConnectedAt
    'Token Expiry Soft' = $s.ConnectedAt.AddMinutes(30)
}
