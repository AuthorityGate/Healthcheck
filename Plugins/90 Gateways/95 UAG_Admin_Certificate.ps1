# Start of Settings
# End of Settings

$Title          = 'UAG Admin Certificate'
$Header         = 'Admin (port 9443) TLS cert posture'
$Comments       = 'Often overlooked vs the user cert. Same expiry concerns apply.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '90 Gateways'
$Severity       = 'P2'
$Recommendation = 'Replace via UAG admin -> Account Settings -> Admin SSL Certificate.'

if (-not (Get-UAGRestSession)) { return }
$c = Get-UAGAdminCertificate
if (-not $c) { return }
[pscustomobject]@{
    SubjectDN  = $c.subjectDn
    IssuerDN   = $c.issuerDn
    NotBefore  = $c.notBefore
    NotAfter   = $c.notAfter
}
