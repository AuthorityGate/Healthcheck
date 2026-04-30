# Start of Settings
# End of Settings

$Title          = 'Enrollment Server Issuance Failures'
$Header         = '[count] Enrollment Server(s) reporting issuance failures in last 24 hours'
$Comments       = 'Issuance failures correlate with CA permission issues, expired template, or mis-set enrollment user.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '93 Enrollment Server'
$Severity       = 'P1'
$Recommendation = 'Audit CA template ACLs. Verify Enrollment Service is granted Enroll + Auto-enroll on the cert template.'

if (-not (Get-HVRestSession)) { return }
try { $tsso = Invoke-HVRest -Path '/v1/config/true-sso' -NoPaging } catch { return }
if (-not $tsso) { return }
foreach ($e in $tsso.enrollment_servers) {
    if ($e.last_24_hours_failures -gt 0) {
        [pscustomobject]@{ ES=$e.host_name; Failures=$e.last_24_hours_failures; Attempts=$e.last_24_hours_attempts }
    }
}
