# Start of Settings
# End of Settings

$Title          = 'Active Sessions per Gateway'
$Header         = 'Per-UAG / Security Server connection load'
$Comments       = 'Skewed load across UAGs indicates a load-balancer health-check problem or session affinity bug.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '60 Sessions'
$Severity       = 'Info'
$Recommendation = 'Verify UAG load balancer rule (round-robin vs least-conn) and edge-service health endpoint reachable.'

if (-not (Get-HVRestSession)) { return }
$s = Get-HVSession
if (-not $s) { return }
$s | Group-Object security_gateway_id | ForEach-Object {
    [pscustomobject]@{ Gateway=$_.Name; ActiveSessions=$_.Count }
}

