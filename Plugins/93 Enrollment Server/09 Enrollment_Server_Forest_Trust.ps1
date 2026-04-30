# Start of Settings
# End of Settings

$Title          = 'Enrollment Server Forest Trust'
$Header         = 'Forest trust for cross-forest True SSO'
$Comments       = "Multi-forest environments need ES + CA in the user's forest, with appropriate trust relationship."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '93 Enrollment Server'
$Severity       = 'P2'
$Recommendation = "Validate forest trust direction (one-way / two-way). Confirm ES enrolls with the user's forest CA."

if (-not (Get-HVRestSession)) { return }
try { $tsso = Invoke-HVRest -Path '/v1/config/true-sso' -NoPaging } catch { return }
if (-not $tsso) { return }
[pscustomobject]@{
    DefaultDomain = $tsso.default_domain_name
    Domains       = if ($tsso.domains) { ($tsso.domains.name -join ', ') } else { '' }
}
