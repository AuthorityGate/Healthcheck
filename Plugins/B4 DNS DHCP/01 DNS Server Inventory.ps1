# Start of Settings
# Operator override: $Global:DNSServerList = @('dns1.fqdn','dns2.fqdn').
# Otherwise we auto-discover via Get-ADDomainController if RSAT is present.
# End of Settings

$Title          = "DNS Server Inventory + Aging / Scavenging"
$Header         = "[count] DNS server(s) probed"
$Comments       = "For each DNS server (auto-discovered via AD or operator-supplied), this plugin reports: server settings, recursion enabled, aging defaults, scavenging interval, root hint count, conditional-forwarder count. Aging + scavenging mis-config is the canonical root cause of stale-record drift across the estate."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B4 DNS DHCP"
$Severity       = "P2"
$Recommendation = "Microsoft baseline: enable aging on every primary AD-integrated zone with NoRefresh + Refresh = 7 days each; enable scavenging on at least one DC every 7 days. Without scavenging, stale A records accumulate and cause connection mis-routing."

$dnsServers = @()
if ($Global:DNSServerList) { $dnsServers = @($Global:DNSServerList) }
else {
    # 1. AD module (works on AD-joined runner with RSAT)
    try { $dnsServers = @((Get-ADDomainController -Filter * -ErrorAction Stop).HostName) } catch { }
    # 2. ipconfig-equivalent: Get-DnsClientServerAddress (built-in, no RSAT)
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
    # 3. LOGONSERVER fallback
    if ($dnsServers.Count -eq 0 -and $env:LOGONSERVER) { $dnsServers = @($env:LOGONSERVER -replace '\\','') }
}
if ($dnsServers.Count -eq 0) {
    [pscustomobject]@{ Note='No DNS servers known. Set $Global:DNSServerList in the runner, or run from an AD-joined machine, or ensure the runner has DNS resolvers configured (ipconfig /all should show them).' }
    return
}
if (-not (Get-Module -ListAvailable -Name DnsServer)) {
    [pscustomobject]@{ Note='DnsServer PowerShell module unavailable. Install via: Add-WindowsCapability -Online -Name "Rsat.Dns.Tools~~~~0.0.1.0".' }
    return
}

foreach ($s in $dnsServers) {
    if (-not $s) { continue }
    try {
        $cfg = Get-DnsServerSetting -ComputerName $s -ErrorAction Stop
        $aging = Get-DnsServerScavenging -ComputerName $s -ErrorAction SilentlyContinue
        $forwarders = @(Get-DnsServerZone -ComputerName $s -ErrorAction SilentlyContinue | Where-Object ZoneType -eq 'Forwarder').Count
        $primaries  = @(Get-DnsServerZone -ComputerName $s -ErrorAction SilentlyContinue | Where-Object ZoneType -eq 'Primary').Count
        [pscustomobject]@{
            Server        = $s
            Recursion     = $cfg.EnableRecursion
            ListenAddrs   = ($cfg.ListenAddresses -join ', ')
            AgingEnabled  = $aging.ScavengingState
            ScavengeIntervalDays = if ($aging) { $aging.ScavengingInterval.Days } else { '' }
            LastScavenge  = if ($aging -and $aging.LastScavengeTime) { $aging.LastScavengeTime.ToString('yyyy-MM-dd HH:mm') } else { '' }
            PrimaryZones  = $primaries
            ConditionalFwd = $forwarders
            VersionRevision = "$($cfg.MajorVersion).$($cfg.MinorVersion).$($cfg.BuildNumber)"
        }
    } catch {
        [pscustomobject]@{ Server=$s; Recursion=''; ListenAddrs=''; AgingEnabled='ERROR'; ScavengeIntervalDays=''; LastScavenge=''; PrimaryZones=''; ConditionalFwd=''; VersionRevision=$_.Exception.Message }
    }
}

$TableFormat = @{
    AgingEnabled = { param($v,$row) if ($v -match 'true|enabled') { 'ok' } elseif ($v -eq 'ERROR') { 'bad' } else { 'warn' } }
}
