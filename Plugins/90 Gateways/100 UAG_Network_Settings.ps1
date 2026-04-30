# Start of Settings
# End of Settings

$Title          = 'UAG Network Settings'
$Header         = 'Network adapter assignments (multi-NIC)'
$Comments       = 'Best-practice: 3-NIC UAG (mgmt, internet-facing, backend). Single-NIC = simpler but less segregated.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '90 Gateways'
$Severity       = 'P3'
$Recommendation = 'If single-NIC, plan migration to 3-NIC for production. Document the routing table.'

if (-not (Get-UAGRestSession)) { return }
$n = Get-UAGNetworkSettings
if (-not $n) { return }
[pscustomobject]@{
    NicCount         = if ($n.nics) { @($n.nics).Count } else { 0 }
    DefaultGateway   = $n.defaultGatewayv4
    DnsServers       = ($n.dnsSettings.dnsServer -join ', ')
    NtpServers       = ($n.ntpSettings.ntpServer -join ', ')
}
