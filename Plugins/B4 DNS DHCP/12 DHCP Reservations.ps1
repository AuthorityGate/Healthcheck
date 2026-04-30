# Start of Settings
# Defensive cap so a 5000-reservation environment doesn't blow up the report.
$MaxReservationsRendered = 1000
# End of Settings

$Title          = "DHCP Reservations Inventory"
$Header         = "[count] DHCP reservation(s) across all scopes (capped at $MaxReservationsRendered)"
$Comments       = "Every static reservation in every scope: hostname, MAC, IP, and per-reservation DNS-update flag. Stale reservations (host long-decommissioned) hold IPs out of the pool indefinitely. Critical for migration projects: reservation list must be migrated to the destination DHCP server before cutover."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B4 DNS DHCP"
$Severity       = "Info"
$Recommendation = "Audit reservations annually. Use Export-DhcpServer to capture full configuration for migration. Servers using static reservations should not also rely on AD-attached DDNS."

if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
    [pscustomobject]@{ Note='DhcpServer module unavailable.' }; return
}
$servers = @()
if ($Global:DHCPServerList) { $servers = @($Global:DHCPServerList) }
else { try { $servers = @((Get-DhcpServerInDC -ErrorAction Stop).DnsName) } catch { } }
if ($servers.Count -eq 0) {
    [pscustomobject]@{ Note='No DHCP servers known.' }; return
}

$rendered = 0
foreach ($s in $servers) {
    if (-not $s) { continue }
    $scopes = @()
    try { $scopes = @(Get-DhcpServerv4Scope -ComputerName $s -ErrorAction Stop) } catch { continue }
    foreach ($sc in $scopes) {
        $rs = @()
        try { $rs = @(Get-DhcpServerv4Reservation -ComputerName $s -ScopeId $sc.ScopeId -ErrorAction SilentlyContinue) } catch { }
        foreach ($r in $rs) {
            if ($rendered -ge $MaxReservationsRendered) { break }
            [pscustomobject]@{
                Server   = $s
                Scope    = $sc.Name
                Hostname = $r.Name
                IP       = $r.IPAddress
                MAC      = $r.ClientId
                Type     = $r.AddressState
                Description = $r.Description
            }
            $rendered++
        }
        if ($rendered -ge $MaxReservationsRendered) { break }
    }
    if ($rendered -ge $MaxReservationsRendered) { break }
}
