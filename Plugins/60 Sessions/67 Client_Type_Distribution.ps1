# Start of Settings
# End of Settings

$Title          = 'Client Type Distribution'
$Header         = 'Sessions distributed by client type (Windows/Mac/iOS/Android/HTML5)'
$Comments       = 'Track HTML5 / mobile share to prioritize feature support.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '60 Sessions'
$Severity       = 'Info'
$Recommendation = 'Surface to capacity / training planning.'

if (-not (Get-HVRestSession)) { return }
$s = Get-HVSession
if (-not $s) { return }
$s | Group-Object client_type | ForEach-Object {
    [pscustomobject]@{ ClientType=$_.Name; Count=$_.Count }
}
