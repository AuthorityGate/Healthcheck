# Start of Settings
# End of Settings

$Title          = "DNS Forward Zones with Aging Settings"
$Header         = "[count] forward zone(s) on the first reachable DNS server"
$Comments       = "Per-zone NoRefresh / Refresh interval, dynamic-update mode, replication scope. Zones in DnsAdmin where aging is OFF will accumulate stale records that block VDI host re-registration on rename."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B4 DNS DHCP"
$Severity       = "P2"
$Recommendation = "Enable aging (NoRefresh=7d, Refresh=7d) on every AD-integrated forward zone. Set DynamicUpdate to SecureOnly to prevent unauthenticated record overwrites."

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
$zones = @()
try { $zones = @(Get-DnsServerZone -ComputerName $server -ErrorAction Stop | Where-Object { -not $_.IsReverseLookupZone }) } catch {
    [pscustomobject]@{ Server=$server; Note=$_.Exception.Message }
    return
}
foreach ($z in $zones) {
    $aging = $null
    try { $aging = Get-DnsServerZoneAging -ZoneName $z.ZoneName -ComputerName $server -ErrorAction Stop } catch { }
    [pscustomobject]@{
        Server          = $server
        Zone            = $z.ZoneName
        ZoneType        = $z.ZoneType
        Replication     = $z.ReplicationScope
        DynamicUpdate   = $z.DynamicUpdate
        AgingEnabled    = if ($aging) { [bool]$aging.AgingEnabled } else { '' }
        NoRefreshDays   = if ($aging) { $aging.NoRefreshInterval.Days } else { '' }
        RefreshDays     = if ($aging) { $aging.RefreshInterval.Days } else { '' }
        IsAutoCreated   = [bool]$z.IsAutoCreated
        IsReadOnly      = [bool]$z.IsReadOnly
    }
}

$TableFormat = @{
    DynamicUpdate = { param($v,$row) if ($v -eq 'NonsecureAndSecure') { 'bad' } elseif ($v -eq 'None') { 'warn' } elseif ($v -eq 'Secure') { 'ok' } else { '' } }
    AgingEnabled  = { param($v,$row) if ($v -eq $true) { 'ok' } elseif ($v -eq $false) { 'warn' } else { '' } }
}
