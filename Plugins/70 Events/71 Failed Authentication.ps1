# Start of Settings
$AuthFailLookbackHours = 24
# Threshold per user - bursts above this trigger a finding.
$PerUserFailThreshold = 5
# End of Settings

$Title          = "Failed Authentications"
$Header         = "Users with more than $PerUserFailThreshold failed broker auths in $AuthFailLookbackHours h"
$Comments       = "Helps spot account lockouts, bad password storms after a password reset, or credential-stuffing attempts."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "70 Events"
$Severity       = "P2"
$Recommendation = "Cross-reference with AD lockout events (4740) and the source IP / client_name to determine intent. Reset passwords or block source if hostile."

try {
    $events = Get-HVAuditEvent -SinceHours $AuthFailLookbackHours -Severities @('AUDIT_FAIL')
} catch { return }
if (-not $events) { return }

$failTypes = 'BROKER_USER_AUTHFAILED','BROKER_USER_AUTHFAILED_DOMAIN_USER','BROKER_USER_AUTHFAILED_USERPASSWORD'

$events | Where-Object { $_.event_type -in $failTypes -and $_.user_id } |
    Group-Object user_id |
    Where-Object { $_.Count -ge $PerUserFailThreshold } |
    ForEach-Object {
        $sample = $_.Group | Select-Object -First 1
        [pscustomobject]@{
            User        = $_.Name
            FailCount   = $_.Count
            LastFail    = ($_.Group | Sort-Object time -Descending | Select-Object -First 1).time |
                           ForEach-Object { (Get-Date '1970-01-01').AddMilliseconds($_).ToLocalTime() }
            LastClient  = $sample.client_name
            LastMessage = $sample.message
        }
    } | Sort-Object FailCount -Descending
