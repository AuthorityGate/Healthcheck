# Start of Settings
# End of Settings

$Title          = 'True SSO Configuration'
$Header         = 'True SSO enrollment / certificate template state'
$Comments       = "Reference: 'Setting Up True SSO' (Horizon Admin Guide). Healthy True SSO has at least one enabled enrollment server, an enabled certificate template, and a healthy CA."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'P2'
$Recommendation = "Verify all enrollment servers are healthy and the certificate template's permissions allow auto-enrollment for Horizon-machines accounts."

if (-not (Get-HVRestSession)) { return }
try { $tsso = Invoke-HVRest -Path '/v1/config/true-sso' -NoPaging } catch { return }
if (-not $tsso) { return }
[pscustomobject]@{
    Enabled              = $tsso.enabled
    Mode                 = $tsso.mode
    DefaultDomain        = $tsso.default_domain_name
    Domains              = ($tsso.domains.name -join ', ')
    EnrollmentServerCount = if ($tsso.enrollment_servers) { @($tsso.enrollment_servers).Count } else { 0 }
    CertificateTemplate  = $tsso.certificate_template_name
}

