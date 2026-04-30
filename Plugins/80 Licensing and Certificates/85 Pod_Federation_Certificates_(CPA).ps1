# Start of Settings
# End of Settings

$Title          = 'Pod Federation Certificates (CPA)'
$Header         = 'CPA inter-pod trust certificate(s)'
$Comments       = 'CPA federation requires inter-pod trust. Cert renewal is manual per-pod.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '80 Licensing and Certificates'
$Severity       = 'P2'
$Recommendation = "Renew via 'vdmadmin -X' or REST endpoint /v1/federation/certificates."

if (-not (Get-HVRestSession)) { return }
try { $f = Invoke-HVRest -Path '/v1/federation/certificates' } catch { return }
if (-not $f) { return }
foreach ($c in $f) {
    [pscustomobject]@{
        Subject  = $c.subject
        Issuer   = $c.issuer
        NotAfter = $c.not_after
    }
}
