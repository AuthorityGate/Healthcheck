# Start of Settings
# End of Settings

$Title          = 'UAG Authentication Methods'
$Header         = '[count] authentication method(s) configured'
$Comments       = 'Auth methods: pass-through, RADIUS, RSA, SAML, certificate, device-cert. Verify the deployed mix matches the design.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '90 Gateways'
$Severity       = 'P2'
$Recommendation = 'Disable unused auth methods; tighten RADIUS shared-secret rotation cycle.'

if (-not (Get-UAGRestSession)) { return }
$a = Get-UAGAuthMethod
if (-not $a) { return }
foreach ($m in $a.authMethodSettingsList) {
    [pscustomobject]@{
        Name    = $m.identifier
        Type    = $m.authMethodType
        Enabled = $m.enabled
    }
}
