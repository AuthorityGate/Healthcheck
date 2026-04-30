# Start of Settings
# End of Settings

$Title          = 'Enrollment Server Eventlog Pull'
$Header         = '[count] Enrollment Server(s) requiring eventlog review'
$Comments       = 'Per-ES Application + System events tell whether the ES is talking to its issuing CA, whether cert requests succeed, and whether the EA cert is healthy. The Horizon REST surfaces high-level status; deep event review requires WinRM into each ES.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '93 Enrollment Server'
$Severity       = 'P3'
$Recommendation = "From an admin workstation: Get-WinEvent -ComputerName <ES-fqdn> -FilterHashtable @{Logname='Application'; ProviderName='VMware Horizon View Enrollment Server'; Level=2,3} -MaxEvents 200. Investigate any errors related to CA reachability, EA cert validation, or impersonation."

if (-not (Get-HVRestSession)) { return }

try { $tsso = Invoke-HVRest -Path '/v1/config/true-sso' -NoPaging } catch { return }
if (-not $tsso) { return }

foreach ($e in @($tsso.enrollment_servers)) {
    $isHealthy = if ($null -ne $e.is_healthy) { [bool]$e.is_healthy } else { $false }
    $needsReview = -not $isHealthy -or ($e.last_24_hours_failures -gt 0)
    if ($needsReview) {
        [pscustomobject]@{
            EnrollmentServer = $e.host_name
            Status           = $e.status
            Healthy          = $isHealthy
            Failures24h      = $e.last_24_hours_failures
            Attempts24h      = $e.last_24_hours_attempts
            EventLogCommand  = "Get-WinEvent -ComputerName $($e.host_name) -FilterHashtable @{Logname='Application'; ProviderName='VMware Horizon View Enrollment Server'; Level=2,3} -MaxEvents 200"
            Reference        = 'KB 2150772 - True SSO troubleshooting'
        }
    }
}
