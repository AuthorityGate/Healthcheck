# Start of Settings
# End of Settings

$Title          = 'Enrollment Server Inventory'
$Header         = '[count] Enrollment Server(s) registered'
$Comments       = "Reference: 'True SSO Enrollment Servers' (Horizon docs). At least 2 ES are recommended for HA."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '93 Enrollment Server'
$Severity       = 'P2'
$Recommendation = 'Deploy a 2nd Enrollment Server for HA. Confirm both are reachable from every CS.'
$RequiredBackend = 'Horizon'

if (-not (Get-HVRestSession)) { return }
try { $tsso = Invoke-HVRest -Path '/v1/config/true-sso' -NoPaging } catch { return }
if (-not $tsso) { return }
foreach ($e in $tsso.enrollment_servers) {
    [pscustomobject]@{
        Name           = $e.host_name
        Status         = $e.status
        Healthy        = $e.is_healthy
        Last24hAttempts = $e.last_24_hours_attempts
        Last24hFailures = $e.last_24_hours_failures
    }
}
