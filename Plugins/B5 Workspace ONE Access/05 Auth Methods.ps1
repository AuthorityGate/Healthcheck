# Start of Settings
# End of Settings

$Title          = "vIDM Authentication Methods"
$Header         = "[count] auth method(s) configured"
$Comments       = "Every authentication method registered with the tenant: Password (Cloud / AD), RSA SecurID, RADIUS, Mobile SSO (iOS / Android), Certificate (Cloud Deployment), VMware Verify, FIDO2, RDP. Determines what an admin can pick when building Access Policy rules."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B5 Workspace ONE Access"
$Severity       = "P2"
$Recommendation = "Privileged-user policies should require Certificate (CBA) or FIDO2 - phishing-resistant MFA. RADIUS push (Duo / RSA OTP) is acceptable but not phishing-resistant. Password as the only configured factor = compliance gap."

if (-not (Get-VIDMRestSession)) { return }
$methods = @(Get-VIDMAuthMethod)
if ($methods.Count -eq 0) {
    [pscustomobject]@{ Note = 'No auth methods returned (insufficient scope or older tenant version).' }
    return
}

foreach ($m in $methods) {
    [pscustomobject]@{
        Name           = $m.name
        Type           = $m.authAdapterType
        Enabled        = [bool]$m.enabled
        ConnectorBound = if ($m.connectorAuthAdapterIds) { @($m.connectorAuthAdapterIds).Count -gt 0 } else { $false }
        PhishingResistant = $m.authAdapterType -in @('CertCloudAuthAdapter','FIDO2AuthAdapter','SmartCardAuthAdapter','MobileSsoAuthAdapter')
    }
}

$TableFormat = @{
    Enabled = { param($v,$row) if ($v -eq $true) { 'ok' } else { '' } }
    PhishingResistant = { param($v,$row) if ($v -eq $true) { 'ok' } else { 'warn' } }
}
