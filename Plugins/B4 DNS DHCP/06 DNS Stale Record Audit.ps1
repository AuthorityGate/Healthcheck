# Start of Settings
$StaleAgeDays = 60
$MaxRecordsRendered = 500
# End of Settings

$Title          = "DNS Stale A-Record Audit"
$Header         = "[count] A-record(s) older than $StaleAgeDays days that aging would scavenge"
$Comments       = "Walks the first AD-integrated forward zone and inventories A-records whose TimeStamp is older than the aging threshold. Without scavenging running, stale records accumulate and break VDI hostname-reuse (the new VM can't register because the old name is still claimed)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B4 DNS DHCP"
$Severity       = "P3"
$Recommendation = "If aging+scavenging are configured, these records will be cleaned automatically over the next refresh+noRefresh cycle. If they aren't, enable scavenging (Get-DnsServerScavenging) on at least one DNS server. Static records (TimeStamp=0) are immune and won't appear."

if (-not (Get-Module -ListAvailable -Name DnsServer)) {
    [pscustomobject]@{ Note = 'DnsServer module not available.' }
    return
}
$dnsServers = @()
if ($Global:DNSServerList) { $dnsServers = @($Global:DNSServerList) }
else {
    try { $dnsServers = @((Get-ADDomainController -Filter * -ErrorAction Stop).HostName) } catch { }
}
if ($dnsServers.Count -eq 0) { return }
$server = $dnsServers | Select-Object -First 1

try {
    $primaryZones = @(Get-DnsServerZone -ComputerName $server -ErrorAction Stop |
        Where-Object { -not $_.IsReverseLookupZone -and $_.ZoneType -eq 'Primary' })
} catch { return }
if ($primaryZones.Count -eq 0) { return }
$zone = $primaryZones[0]

$cutoff = (Get-Date).AddDays(-$StaleAgeDays)
try {
    $records = @(Get-DnsServerResourceRecord -ZoneName $zone.ZoneName -RRType A -ComputerName $server -ErrorAction Stop |
        Where-Object { $_.TimeStamp -and [datetime]$_.TimeStamp -lt $cutoff })
} catch {
    [pscustomobject]@{ Note = "Record-walk failed: $($_.Exception.Message)" }
    return
}

if ($records.Count -eq 0) {
    [pscustomobject]@{ Zone=$zone.ZoneName; Note="No stale records (older than $StaleAgeDays days)." }
    return
}
$rendered = 0
foreach ($r in ($records | Sort-Object TimeStamp)) {
    if ($rendered -ge $MaxRecordsRendered) { break }
    [pscustomobject]@{
        Zone        = $zone.ZoneName
        HostName    = $r.HostName
        IPv4Address = $r.RecordData.IPv4Address
        TimeStamp   = ([datetime]$r.TimeStamp).ToString('yyyy-MM-dd HH:mm')
        AgeDays     = [int]((Get-Date) - [datetime]$r.TimeStamp).TotalDays
    }
    $rendered++
}

$TableFormat = @{
    AgeDays = { param($v,$row) if ([int]"$v" -gt 180) { 'bad' } elseif ([int]"$v" -gt 90) { 'warn' } else { '' } }
}
