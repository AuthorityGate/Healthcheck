# Start of Settings
# End of Settings

$Title          = 'FIDO2 / Smart Card Phishing-Resistant MFA'
$Header         = "Phishing-resistant MFA configuration"
$Comments       = "Phishing-resistant MFA = smart card or FIDO2 (cert-based, not OTP). Surfaces whether Horizon is configured for either. Modern security baselines (NIST 800-63B AAL3, CISA Zero Trust) require phishing-resistant MFA for privileged access."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'B2 Multi-Factor Auth'
$Severity       = 'P2'
$Recommendation = "RADIUS push (Duo, RSA OTP) is acceptable but not phishing-resistant. Plan migration to FIDO2 Security Keys (via vIDM federation) or smart cards for high-assurance scopes. Document exception scopes."

if (-not (Get-HVRestSession)) { return }

# Smart card detection at CS layer
$smartCardCount = 0
$cardEnabledServers = @()
try {
    $cs = Invoke-HVRest -Path '/v1/monitor/connection-servers' -NoPaging
    foreach ($c in @($cs)) {
        $cas = $c.certificate_authentication_settings
        if ($cas -and $cas.is_certificate_authentication_enabled) {
            $smartCardCount++
            $cardEnabledServers += $c.name
        }
    }
} catch { }

# FIDO2 typically delivered via vIDM federation - check SAML authenticator presence
$samlAuthCount = 0
try {
    $samlList = Invoke-HVRest -Path '/v1/config/saml-authenticators' -NoPaging
    $samlAuthCount = @($samlList).Count
} catch { }

[pscustomobject]@{
    Mechanism            = 'Smart Card (X.509)'
    ConfiguredServers    = $smartCardCount
    Servers              = ($cardEnabledServers -join ', ')
    Note                 = if ($smartCardCount -eq 0) { 'Not configured at CS layer.' } else { 'Active.' }
    PhishingResistant    = $true
}

[pscustomobject]@{
    Mechanism            = 'FIDO2 (via SAML federation)'
    ConfiguredServers    = $samlAuthCount
    Servers              = '(via IdP)'
    Note                 = if ($samlAuthCount -eq 0) { 'No SAML federation - FIDO2 cannot be delivered.' } else { 'SAML federation present - confirm IdP enforces FIDO2.' }
    PhishingResistant    = $true
}

$TableFormat = @{
    ConfiguredServers = { param($v,$row) if ($v -eq 0) { 'warn' } else { '' } }
}
