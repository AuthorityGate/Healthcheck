# Start of Settings
# End of Settings

$Title          = 'SAML 2.0 Authenticator'
$Header         = '[count] SAML 2.0 Authenticators configured'
$Comments       = "Reference: Horizon Admin Guide -> 'Configure SAML Authentication'. Required for Workspace ONE Access / TrueSSO front-ends. Stale authenticators with expired metadata cause silent login failure."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'P2'
$Recommendation = "Validate IdP metadata still loads, cert chain to IdP is trusted, and 'Allow SAML 2.0 Authentication' is set per-pod policy."

if (-not (Get-HVRestSession)) { return }
try { $sa = Invoke-HVRest -Path '/v1/config/saml-authenticators' } catch { return }
if (-not $sa) { return }
foreach ($s in $sa) {
    [pscustomobject]@{
        Label              = $s.label
        Description        = $s.description
        StaticMetadataUrl  = $s.static_metadata_url
        IdpEntityId        = $s.idp_entity_id
        Enabled            = $s.enabled
        Default            = $s.default
    }
}

