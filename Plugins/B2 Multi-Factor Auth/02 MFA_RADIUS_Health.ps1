# Start of Settings
# End of Settings

$Title          = 'RADIUS Server Reachability + Health'
$Header         = "[count] RADIUS server(s) probed"
$Comments       = "Probes each RADIUS server configured in Horizon for TCP reachability + health. Primary + secondary tested. Without TCP reachability = RADIUS auth fails fleet-wide."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'B2 Multi-Factor Auth'
$Severity       = 'P1'
$Recommendation = "Both primary and secondary RADIUS must be reachable. If only one responds, the deployment is at MFA outage risk. Verify firewall, DNS, RADIUS service running."

if (-not (Get-HVRestSession)) { return }

try { $radList = Invoke-HVRest -Path '/v1/config/radius' -NoPaging } catch { return }
if (-not $radList) { return }

function _testTcp { param($host, $port)
    if (-not $host) { return $false }
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $async = $tcp.BeginConnect($host, $port, $null, $null)
        $ok = $async.AsyncWaitHandle.WaitOne(2000, $false)
        $r = ($ok -and $tcp.Connected)
        $tcp.Close()
        return $r
    } catch { return $false }
}

foreach ($r in @($radList)) {
    foreach ($side in 'primary_auth_server','secondary_auth_server') {
        $s = $r.$side
        if (-not $s -or -not $s.host_name) { continue }
        $port = if ($s.authentication_port) { [int]$s.authentication_port } else { 1812 }
        $reachable = _testTcp $s.host_name $port

        [pscustomobject]@{
            Authenticator = $r.label
            Side          = ($side -replace '_auth_server','').ToUpper()
            Server        = $s.host_name
            Port          = $port
            AuthType      = $s.authentication_type
            Timeout       = $s.server_timeout
            Reachable     = if ($reachable) { 'OK' } else { 'FAIL' }
        }
    }
}

$TableFormat = @{
    Reachable = { param($v,$row) if ($v -eq 'FAIL') { 'bad' } else { '' } }
}
