# Start of Settings
# End of Settings

$Title          = "Connection Server Cert Friendly-Name 'vdm'"
$Header         = "[count] CS certificate(s) without 'vdm' friendly name"
$Comments       = "Reference: 'Replace the Default Server Certificate' (Horizon docs). The friendly name MUST be 'vdm' for the CS service to bind to it on startup."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '80 Licensing and Certificates'
$Severity       = 'P1'
$Recommendation = "On the CS: certlm.msc -> Personal -> Certificates -> right-click cert -> Properties -> Friendly name = 'vdm'. Restart 'VMware Horizon Connection Server'."

if (-not (Get-HVRestSession)) { return }
$cs = Get-HVConnectionServer
if (-not $cs) { return }
foreach ($c in $cs) {
    if (-not $c.certificate -or -not $c.certificate.valid) {
        [pscustomobject]@{
            ConnectionServer = $c.name
            CertSubject      = $c.certificate.subject
            CertValid        = $c.certificate.valid
            FriendlyName     = '(unverifiable from REST - check on the CS via certlm.msc)'
        }
    }
}

