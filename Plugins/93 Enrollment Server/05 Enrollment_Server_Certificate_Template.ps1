# Start of Settings
# End of Settings

$Title          = 'Enrollment Server Certificate Template'
$Header         = 'Cert template name + key spec for True SSO'
$Comments       = "Reference: 'Configure the Certificate Template Used for True SSO' (Horizon docs). Wrong key spec / EKU breaks logon."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '93 Enrollment Server'
$Severity       = 'P1'
$Recommendation = "Template must duplicate 'Smartcard Logon' template, with private-key spec 'Allow private key to be exported' = NO, EKU = Smart Card Logon."

if (-not (Get-HVRestSession)) { return }
try { $tsso = Invoke-HVRest -Path '/v1/config/true-sso' -NoPaging } catch { return }
if (-not $tsso) { return }
[pscustomobject]@{
    CertificateTemplate = $tsso.certificate_template_name
    Mode                = $tsso.mode
    DefaultDomain       = $tsso.default_domain_name
}
