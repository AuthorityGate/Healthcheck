# Start of Settings
# End of Settings

$Title          = "DNS Recursion + Security Posture"
$Header         = "Per-server: recursion-allowed, root-hints state, EnableEDnsProbes, secure-cache-against-pollution"
$Comments       = "Public-facing DNS servers (or DNS exposed to untrusted networks) MUST disable recursion - open-recursive DNS is exploited for cache poisoning + DDoS amplification. Even internal-only servers should have SecureResponses + EnableEDnsProbes set per Microsoft's secure-by-default profile."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B4 DNS DHCP"
$Severity       = "P1"
$Recommendation = "DNS servers reachable from outside the trust boundary MUST have recursion disabled. AD-joined internal-only servers should keep recursion ON but verify root hints are healthy and forwarders point at trusted DNS only."

if (-not (Get-Module -ListAvailable -Name DnsServer)) {
    [pscustomobject]@{ Note = 'DnsServer module not available. Install RSAT-DNS-Server.' }
    return
}

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
if ($dnsServers.Count -eq 0) { return }

foreach ($s in $dnsServers) {
    try {
        $rec = Get-DnsServerRecursion -ComputerName $s -ErrorAction Stop
        $rh  = @(Get-DnsServerRootHint -ComputerName $s -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            Server               = $s
            RecursionEnabled     = [bool]$rec.Enable
            RetryInterval        = $rec.RetryInterval.TotalSeconds
            Timeout              = $rec.Timeout.TotalSeconds
            AdditionalTimeout    = $rec.AdditionalTimeout.TotalSeconds
            RootHintCount        = $rh.Count
            RootHintsHealthy     = ($rh.Count -ge 13)
        }
    } catch {
        [pscustomobject]@{ Server=$s; RecursionEnabled='ERROR'; RetryInterval=''; Timeout=''; AdditionalTimeout=''; RootHintCount=''; RootHintsHealthy=$_.Exception.Message }
    }
}

$TableFormat = @{
    RecursionEnabled  = { param($v,$row) if ($v -eq $true) { 'ok' } elseif ($v -eq $false) { 'warn' } else { 'bad' } }
    RootHintsHealthy  = { param($v,$row) if ($v -eq $true) { 'ok' } elseif ($v -eq $false) { 'bad' } else { '' } }
}
