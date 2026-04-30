# Start of Settings
# End of Settings

$Title          = "DHCP Scope Utilization + Lease Duration"
$Header         = "[count] scope(s) inventoried with usage + lease duration"
$Comments       = "Per-scope: name, range, exclusion count, current % full, lease duration (hold time), and DNS update flags. Saturated scopes (>80% leased) trigger 'no IP available' calls during login storms."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B4 DNS DHCP"
$Severity       = "P2"
$Recommendation = "Scopes >80% utilized: extend the range, shorten lease duration, or add reservations for stable hosts. VDI scopes typically need 2-4 hour leases (not the default 8 days) to avoid lease pool exhaustion during refresh cycles."

if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
    [pscustomobject]@{ Note='DhcpServer module unavailable.' }; return
}
$servers = @()
if ($Global:DHCPServerList) { $servers = @($Global:DHCPServerList) }
else { try { $servers = @((Get-DhcpServerInDC -ErrorAction Stop).DnsName) } catch { } }
if ($servers.Count -eq 0) {
    [pscustomobject]@{ Note='No DHCP servers known.' }; return
}

foreach ($s in $servers) {
    if (-not $s) { continue }
    $scopes = @()
    try { $scopes = @(Get-DhcpServerv4Scope -ComputerName $s -ErrorAction Stop) } catch { continue }
    foreach ($sc in $scopes) {
        $stats = $null; $excl = 0; $reserve = 0; $leases = 0
        try { $stats = Get-DhcpServerv4ScopeStatistics -ScopeId $sc.ScopeId -ComputerName $s -ErrorAction Stop } catch { }
        try { $excl = @(Get-DhcpServerv4ExclusionRange -ComputerName $s -ScopeId $sc.ScopeId -ErrorAction SilentlyContinue).Count } catch { }
        try { $reserve = @(Get-DhcpServerv4Reservation -ComputerName $s -ScopeId $sc.ScopeId -ErrorAction SilentlyContinue).Count } catch { }
        try { $leases = @(Get-DhcpServerv4Lease -ComputerName $s -ScopeId $sc.ScopeId -ErrorAction SilentlyContinue).Count } catch { }
        [pscustomobject]@{
            Server         = $s
            Scope          = $sc.Name
            ScopeId        = $sc.ScopeId
            Range          = "$($sc.StartRange) - $($sc.EndRange)"
            State          = $sc.State
            LeaseDuration  = $sc.LeaseDuration
            PercentInUse   = if ($stats) { [math]::Round($stats.PercentageInUse, 1) } else { '' }
            FreeAddresses  = if ($stats) { $stats.Free } else { '' }
            InUseAddresses = if ($stats) { $stats.InUse } else { '' }
            Exclusions     = $excl
            Reservations   = $reserve
            ActiveLeases   = $leases
            DnsUpdate      = (Get-DhcpServerv4DnsSetting -ComputerName $s -ScopeId $sc.ScopeId -ErrorAction SilentlyContinue).DynamicUpdates
        }
    }
}

$TableFormat = @{
    PercentInUse = { param($v,$row) if ([double]"$v" -gt 90) { 'bad' } elseif ([double]"$v" -gt 80) { 'warn' } else { '' } }
    State        = { param($v,$row) if ($v -eq 'Active') { 'ok' } elseif ($v -eq 'Inactive') { 'warn' } else { '' } }
    LeaseDuration = { param($v,$row) try { if (([timespan]$v).TotalDays -gt 7) { 'warn' } else { '' } } catch { '' } }
}
