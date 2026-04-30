# Start of Settings
# End of Settings

$Title          = 'UAG TLS Profile'
$Header         = 'TLS protocol versions accepted'
$Comments       = 'Reference: UAG hardening guide. TLS 1.0 / 1.1 must be disabled (PCI-DSS, HIPAA).'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '90 Gateways'
$Severity       = 'P1'
$Recommendation = 'UAG admin -> System Configuration -> TLS Named Settings: enable TLS 1.2 + 1.3, disable older.'

if (-not (Get-UAGRestSession)) { return }
$s = Get-UAGSystemSettings
if (-not $s) { return }
[pscustomobject]@{
    SslMinProtocolVersion = $s.sslMinProtocolVersion
    CipherSuites          = $s.cipherSuites
}
