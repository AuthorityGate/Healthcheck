# Start of Settings
# End of Settings

$Title          = "DNS Conditional Forwarders"
$Header         = "[count] conditional forwarder zone(s)"
$Comments       = "Per-zone conditional forwarders that route a specific suffix to specific upstream IPs (e.g., partner.com -> 10.99.x.x). Critical for cross-domain Horizon brokering, federated SAML lookups, and hybrid Azure AD."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B4 DNS DHCP"
$Severity       = "Info"
$Recommendation = "Verify each forwarder's master IPs are reachable. AD-replicated forwarders propagate; standalone forwarders only exist on the configured server. UseRecursion=false on the partner zone to keep traffic local."

$dnsServers = @()
if ($Global:DNSServerList) { $dnsServers = @($Global:DNSServerList) }
else {
    try { $dnsServers = @((Get-ADDomainController -Filter * -ErrorAction Stop).HostName) } catch { }
    if ($dnsServers.Count -eq 0) {
        try {
            $local = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.ServerAddresses -and $_.InterfaceAlias -notmatch 'Loopback|isatap' } |
                ForEach-Object { $_.ServerAddresses } |
                Where-Object { $_ -and $_ -ne '127.0.0.1' -and $_ -notmatch '^169\.254' } |
                Select-Object -Unique)
            if ($local) { $dnsServers = $local }
        } catch { }
    }
}
if ($dnsServers.Count -eq 0) {
    [pscustomobject]@{ Note='No DNS servers known. Set $Global:DNSServerList, run from AD-joined host, or ensure DNS resolvers are configured.' }
    return
}
if (-not (Get-Module -ListAvailable -Name DnsServer)) {
    [pscustomobject]@{ Note='DnsServer PowerShell module unavailable.' }
    return
}
$server = $dnsServers | Select-Object -First 1
$fwds = @()
try { $fwds = @(Get-DnsServerZone -ComputerName $server -ErrorAction Stop | Where-Object ZoneType -eq 'Forwarder') } catch {
    [pscustomobject]@{ Server=$server; Note=$_.Exception.Message }
    return
}
if ($fwds.Count -eq 0) {
    [pscustomobject]@{ Server=$server; Zone='(none)'; Masters=''; UseRootHints=''; Note='No conditional forwarders configured.' }
    return
}
foreach ($z in $fwds) {
    [pscustomobject]@{
        Server      = $server
        Zone        = $z.ZoneName
        Masters     = ($z.MasterServers -join ', ')
        UseRootHints = $z.UseRootHints
        Replication = $z.ReplicationScope
        ForwardingTimeout = $z.ForwarderTimeout
    }
}
