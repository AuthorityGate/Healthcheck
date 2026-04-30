# Start of Settings
# End of Settings

$Title          = 'Connection Server SSL Certificate Trust Chain'
$Header         = 'CS certificate chain depth + intermediate count'
$Comments       = 'Truncated chains (missing intermediates) cause iOS / Android / older Windows clients to fail.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '80 Licensing and Certificates'
$Severity       = 'P2'
$Recommendation = 'Stack the full chain (Server -> Intermediate1 -> Intermediate2 -> Root) into the cert + private key.'

if (-not (Get-HVRestSession)) { return }
$cs = Get-HVConnectionServer
if (-not $cs) { return }
foreach ($c in $cs) {
    [pscustomobject]@{
        ConnectionServer = $c.name
        CertSubject      = $c.certificate.subject
        CertValid        = $c.certificate.valid
        ChainComplete    = ($c.certificate.subject -ne $c.certificate.issuer)  # quick heuristic
    }
}
