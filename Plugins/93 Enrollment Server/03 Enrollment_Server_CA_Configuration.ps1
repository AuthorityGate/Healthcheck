# Start of Settings
# End of Settings

$Title          = 'Enrollment Server CA Configuration'
$Header         = '[count] CA(s) registered with True SSO'
$Comments       = 'Enrollment Server requires at least one Enterprise Issuing CA. Multiple CAs allow forest-wide deployments.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '93 Enrollment Server'
$Severity       = 'P2'
$Recommendation = "Confirm CA in 'Issuing' state and reachable. Test cert issuance via certreq.exe -submit."

if (-not (Get-HVRestSession)) { return }
try { $tsso = Invoke-HVRest -Path '/v1/config/true-sso' -NoPaging } catch { return }
if (-not $tsso) { return }
foreach ($c in $tsso.certificate_authorities) {
    [pscustomobject]@{
        CA          = $c.ca_name
        Hostname    = $c.host_name
        Status      = $c.status
    }
}
