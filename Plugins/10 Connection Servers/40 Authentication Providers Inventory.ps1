# Start of Settings
# End of Settings

$Title          = "Authentication Providers Inventory"
$Header         = "[count] auth provider configuration(s) registered"
$Comments       = "All RADIUS authenticators, SAML authenticators, smart-card configurations, and TrueSSO connectors registered with the pod, with version + connectivity state. Used to plan auth-stack consolidation and IdP rotations during upgrades."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "10 Connection Servers"
$Severity       = "Info"
$Recommendation = "Document the active provider for each access path (internal, external/UAG, kiosk). Stale providers (no recent traffic) should be removed. Stale signing certs invalidate SAML in flight."

if (-not (Get-HVRestSession)) { return }

$radius   = @(Get-HVRADIUSAuthenticator)
$saml     = @(Get-HVSAMLAuthenticator)
$cert     = @(Get-HVCertSSOConnector)
$tsso     = @(Get-HVTrueSSO)
$mradius  = @(Get-HVMonitorRADIUS)
$msaml    = @(Get-HVMonitorSAML)
$mtsso    = @(Get-HVMonitorTrueSSO)

foreach ($r in $radius) {
    [pscustomobject]@{
        Provider = 'RADIUS'
        Name     = $r.label
        Notes    = $r.description
        Primary  = if ($r.primary_auth_server) { $r.primary_auth_server.host_name_or_ip_address } else { '' }
        Secondary= if ($r.secondary_auth_server) { $r.secondary_auth_server.host_name_or_ip_address } else { '' }
        State    = ($mradius | Where-Object { $_.id -eq $r.id } | Select-Object -First 1).status
        Default  = [bool]$r.is_default
    }
}
foreach ($s in $saml) {
    [pscustomobject]@{
        Provider = 'SAML'
        Name     = $s.label
        Notes    = $s.description
        Primary  = $s.idp_entity_id
        Secondary= $s.static_metadata_url
        State    = ($msaml | Where-Object { $_.id -eq $s.id } | Select-Object -First 1).status
        Default  = [bool]$s.is_enabled
    }
}
foreach ($c in $cert) {
    [pscustomobject]@{
        Provider = 'CertSSO'
        Name     = $c.name
        Notes    = $c.description
        Primary  = $c.domain
        Secondary= ''
        State    = 'Configured'
        Default  = [bool]$c.is_enabled
    }
}
foreach ($t in $tsso) {
    [pscustomobject]@{
        Provider = 'TrueSSO'
        Name     = $t.name
        Notes    = "Mode=$($t.mode); Domain=$($t.default_domain)"
        Primary  = $t.certificate_template
        Secondary= ''
        State    = ($mtsso | Where-Object { $_.id -eq $t.id } | Select-Object -First 1).status
        Default  = [bool]$t.is_enabled
    }
}

$TableFormat = @{
    State = { param($v,$row) if ($v -match 'OK') { 'ok' } elseif ($v -and $v -ne 'Configured') { 'warn' } else { '' } }
}
