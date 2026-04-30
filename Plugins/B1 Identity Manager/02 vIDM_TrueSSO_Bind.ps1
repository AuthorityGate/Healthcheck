# Start of Settings
# End of Settings

$Title          = 'vIDM True SSO Bind State'
$Header         = "[count] CS pod(s) - True SSO + IdP bind state"
$Comments       = "True SSO + vIDM federation = user authenticates at vIDM (incl. MFA / Workspace ONE), Horizon receives a SAML assertion + uses Enrollment Server to mint a short-lived cert for desktop logon. Surfaces the configured TSSO setting + which SAML authenticator it ties to."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'B1 Identity Manager'
$Severity       = 'P2'
$Recommendation = "If True SSO is enabled but no SAML authenticator is bound, primary auth path is degraded. Configure both for the seamless flow. Test by logging in via vIDM and watching the Horizon Client - no second password prompt should appear."

if (-not (Get-HVRestSession)) { return }

try { $tsso = Invoke-HVRest -Path '/v1/config/true-sso' -NoPaging } catch { return }
if (-not $tsso) { return }

[pscustomobject]@{
    TrueSSOEnabled        = $tsso.enabled
    Mode                  = $tsso.mode
    DefaultAuthenticator  = $tsso.default_saml_authenticator_label
    EnrollmentServerCount = if ($tsso.enrollment_servers) { @($tsso.enrollment_servers).Count } else { 0 }
    CertificateAuthorityCount = if ($tsso.certificate_authorities) { @($tsso.certificate_authorities).Count } else { 0 }
    LegacyMode            = $tsso.legacy_mode
    Status                = $tsso.status
}

$TableFormat = @{
    TrueSSOEnabled       = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
    DefaultAuthenticator = { param($v,$row) if (-not $v) { 'warn' } else { '' } }
}
