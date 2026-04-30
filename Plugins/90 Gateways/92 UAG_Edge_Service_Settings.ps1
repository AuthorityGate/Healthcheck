# Start of Settings
# End of Settings

$Title          = 'UAG Edge Service Settings'
$Header         = '[count] edge service(s) configured'
$Comments       = 'Edge services include Horizon, Web Reverse Proxy, Tunnel, Content Gateway, Secure Email Gateway. Each enabled service is an attack surface.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '90 Gateways'
$Severity       = 'P2'
$Recommendation = 'Disable any edge service not in active use; disable IPv6 edge services if unused.'

if (-not (Get-UAGRestSession)) { return }
$e = Get-UAGEdgeSettings
if (-not $e) { return }
foreach ($s in $e.edgeServiceSettingsList) {
    [pscustomobject]@{
        Name       = $s.identifier
        Enabled    = $s.enabled
        ProxyMode  = $s.proxyMode
        Endpoint   = $s.proxyDestinationUrl
    }
}
