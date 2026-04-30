# Start of Settings
# End of Settings

$Title          = 'CS ADAM/LDAP Replication Health'
$Header         = "[count] CS pair(s) with replication issues"
$Comments       = "Each Horizon CS hosts an ADAM (AD LDS) instance with the pod's state. Replication keeps state consistent. Replication lag/failure = entitlement drift, pool inconsistency, broker decisions on stale data."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'P1'
$Recommendation = "Run vdmadmin -L -list on a CS to see replication status. Investigate any failed pair: typically credential issue, network/firewall block on LDAP, or one CS recently rebooted/reseeded. Replication lag > 5 min = active investigation."

if (-not (Get-HVRestSession)) { return }

# REST API surfaces server-health which includes LDAP state per CS.
try { $cs = Invoke-HVRest -Path '/v1/monitor/connection-servers' -NoPaging } catch { return }
if (-not $cs) { return }

foreach ($c in @($cs)) {
    $ldap = $null
    if ($c.services) {
        $ldap = $c.services | Where-Object { $_.service_name -match 'LDAP|AD LDS' } | Select-Object -First 1
    }
    if (-not $ldap) {
        # Aggregate health from all services
        $degraded = @($c.services | Where-Object { $_.status -ne 'OK' })
        if ($degraded -and $degraded.Count -gt 0) {
            foreach ($d in $degraded) {
                [pscustomobject]@{
                    ConnectionServer = $c.name
                    Service          = $d.service_name
                    Status           = $d.status
                    Note             = if ($d.message) { $d.message } else { 'Service reporting non-OK state.' }
                }
            }
        }
    } elseif ($ldap.status -ne 'OK') {
        [pscustomobject]@{
            ConnectionServer = $c.name
            Service          = $ldap.service_name
            Status           = $ldap.status
            Note             = if ($ldap.message) { $ldap.message } else { 'LDAP service degraded.' }
        }
    }
}

$TableFormat = @{
    Status = { param($v,$row) if ($v -ne 'OK' -and $v) { 'bad' } else { '' } }
}
