# Start of Settings
# End of Settings

$Title          = "Gateways (UAG / Security Server)"
$Header         = "[count] gateway(s) registered"
$Comments       = "All registered Unified Access Gateways and legacy Security Servers, with version + tunnel state."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "90 Gateways"
$Severity       = "P2"
$Recommendation = "Any gateway not in 'OK' state should be investigated immediately - affects external access. UAGs not on the latest LTSR are at risk for accumulating CVEs; plan upgrade quarterly."

$gw = Get-HVGateway
if (-not $gw) { return }

foreach ($g in $gw) {
    [pscustomobject]@{
        Name             = $g.name
        Type             = $g.type
        Version          = $g.version
        Address          = $g.address
        Status           = $g.status
        ConnectionServer = $g.connection_server_name
        ActiveSessions   = $g.active_connection_count
        SecureTunnel     = $g.secure_tunnel
        BlastTunnel      = $g.blast_secure_gateway
        PCoIPGateway     = $g.pcoip_secure_gateway
    }
}

$TableFormat = @{
    Status = { param($v,$row) if ($v -ne 'OK') { 'bad' } else { 'ok' } }
}
