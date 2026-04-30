# Start of Settings
# End of Settings

$Title          = 'Enrollment Server Time Sync'
$Header         = 'Domain controller / ES clock skew check'
$Comments       = 'Cert issuance needs < 5 minutes skew between ES, CA, and DC.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '93 Enrollment Server'
$Severity       = 'P1'
$Recommendation = 'Verify w32tm /query /status on each Enrollment Server.'

if (-not (Get-HVRestSession)) { return }
try { $tsso = Invoke-HVRest -Path '/v1/config/true-sso' -NoPaging } catch { return }
if (-not $tsso) { return }
[pscustomobject]@{
    Note = 'PSRemoting to each ES would be required to query w32tm. Manually confirm time sync on each.'
}
