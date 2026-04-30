# Start of Settings
# End of Settings

$Title          = 'UAG Server Certificate'
$Header         = 'End-user TLS cert posture'
$Comments       = 'UAG end-user cert hosts the public FQDN. Self-signed = browser warnings; expired = total outage.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '90 Gateways'
$Severity       = 'P1'
$Recommendation = "Replace with public-CA cert from a trusted issuer (DigiCert, Sectigo, Let's Encrypt). Auto-renew via UAG admin REST."

if (-not (Get-UAGRestSession)) { return }
$c = Get-UAGCertificate
if (-not $c) { return }
[pscustomobject]@{
    SubjectDN     = $c.subjectDn
    IssuerDN      = $c.issuerDn
    SerialNumber  = $c.serialNumber
    NotBefore     = $c.notBefore
    NotAfter      = $c.notAfter
    SignAlg       = $c.signatureAlgorithm
}
