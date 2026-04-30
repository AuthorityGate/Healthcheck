# Start of Settings
# End of Settings

$Title          = 'True SSO Recent Issuance Rate'
$Header         = 'Issuance rate over the last 24 hours'
$Comments       = 'Sustained high issuance rate (>10/sec) requires CA capacity planning.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '93 Enrollment Server'
$Severity       = 'Info'
$Recommendation = 'If issuance is high, scale the CA cluster or cache certs longer.'

if (-not (Get-HVRestSession)) { return }
try { $tsso = Invoke-HVRest -Path '/v1/config/true-sso' -NoPaging } catch { return }
if (-not $tsso) { return }
$total = 0
$failed = 0
foreach ($e in $tsso.enrollment_servers) {
    $total += $e.last_24_hours_attempts
    $failed += $e.last_24_hours_failures
}
[pscustomobject]@{
    TotalAttempts24h = $total
    Failed24h        = $failed
    SuccessRate      = if ($total -gt 0) { "{0:N1}%" -f ((($total - $failed) / $total) * 100) } else { 'n/a' }
}
