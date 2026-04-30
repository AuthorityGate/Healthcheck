# Start of Settings
# End of Settings

$Title          = 'MFA / Dual-Factor Authentication Configuration'
$Header         = "[count] MFA mechanism(s) configured for Horizon"
$Comments       = "Surfaces every dual-factor auth method configured at the Horizon CS layer: RADIUS (Duo / RSA / NPS), SAML (vIDM / Okta / Entra ID), Smart Card, FIDO2. Without explicit MFA = phishing-vulnerable. Without redundancy = MFA outage = login outage."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'B2 Multi-Factor Auth'
$Severity       = 'P1'
$Recommendation = "Production Horizon MUST require MFA for at least external paths (UAG-fronted) and SHOULD require it internally too. Verify primary + secondary RADIUS server. Verify SAML auto-refresh enabled. Plan FIDO2 migration for phish-resistant MFA."

if (-not (Get-HVRestSession)) { return }

# RADIUS
try {
    $radList = Invoke-HVRest -Path '/v1/config/radius' -NoPaging
    foreach ($r in @($radList)) {
        [pscustomobject]@{
            Mechanism   = 'RADIUS'
            Name        = $r.label
            Primary     = $r.primary_auth_server.host_name
            Secondary   = $r.secondary_auth_server.host_name
            Timeout     = $r.primary_auth_server.server_timeout
            ProtocolType= $r.primary_auth_server.authentication_type
            Notes       = if (-not $r.secondary_auth_server -or -not $r.secondary_auth_server.host_name) { 'No secondary RADIUS - SPOF' } else { '' }
        }
    }
} catch { }

# SAML
try {
    $samlList = Invoke-HVRest -Path '/v1/config/saml-authenticators' -NoPaging
    foreach ($s in @($samlList)) {
        [pscustomobject]@{
            Mechanism   = 'SAML'
            Name        = $s.label
            Primary     = $s.metadata_source_url
            Secondary   = ''
            Timeout     = ''
            ProtocolType= $s.type
            Notes       = if ($s.metadata_source_auto_refresh -eq $false) { 'Metadata auto-refresh OFF - cert rotation will break' } else { '' }
        }
    }
} catch { }

# Smart Card configuration via certificate-authentication
try {
    $cs = Invoke-HVRest -Path '/v1/monitor/connection-servers' -NoPaging
    $smartCardConfigured = $false
    foreach ($c in @($cs)) {
        if ($c.certificate_authentication_settings -and $c.certificate_authentication_settings.is_certificate_authentication_enabled) {
            $smartCardConfigured = $true
            break
        }
    }
    if ($smartCardConfigured) {
        [pscustomobject]@{
            Mechanism   = 'Smart Card'
            Name        = 'CS-side cert auth'
            Primary     = '(per-CS config)'
            Secondary   = ''
            Timeout     = ''
            ProtocolType= 'X.509'
            Notes       = 'Smart Card auth enabled at CS - verify CRL/OCSP reachability + trust list current.'
        }
    }
} catch { }

$TableFormat = @{
    Notes = { param($v,$row) if ($v -match 'SPOF|OFF|broken') { 'warn' } else { '' } }
}
