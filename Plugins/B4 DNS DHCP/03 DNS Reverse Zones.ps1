# Start of Settings
# End of Settings

$Title          = "DNS Reverse Lookup Zones"
$Header         = "[count] reverse zone(s)"
$Comments       = "Reverse lookup zones (in-addr.arpa) per server. Missing reverse zones cause SQL/Kerberos/Active Directory tools to log warnings and slow down by 5-10s on each connection while waiting for the timeout. Critical for SMB / Kerberos auth path latency."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B4 DNS DHCP"
$Severity       = "P3"
$Recommendation = "Each subnet should have a corresponding reverse zone with PTR registration enabled. Empty zones should be removed. AD-integrated reverse zones should match the forward-zone replication scope."

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
$rev = @()
try { $rev = @(Get-DnsServerZone -ComputerName $server -ErrorAction Stop | Where-Object { $_.IsReverseLookupZone }) } catch {
    [pscustomobject]@{ Server=$server; Note=$_.Exception.Message }
    return
}
foreach ($z in $rev) {
    $records = $null
    try { $records = @(Get-DnsServerResourceRecord -ZoneName $z.ZoneName -ComputerName $server -RRType PTR -ErrorAction SilentlyContinue).Count } catch { }
    [pscustomobject]@{
        Server         = $server
        Zone           = $z.ZoneName
        ZoneType       = $z.ZoneType
        Replication    = $z.ReplicationScope
        PTRRecords     = $records
        DynamicUpdate  = $z.DynamicUpdate
    }
}
