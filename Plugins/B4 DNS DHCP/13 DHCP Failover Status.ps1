# Start of Settings
# End of Settings

$Title          = "DHCP Failover Relationship Status"
$Header         = "[count] failover relationship(s) across DHCP servers"
$Comments       = "DHCP failover binds two DHCP servers in a load-balance or hot-standby relationship so a single server outage does not stop new lease grants. This plugin enumerates every failover relationship and its current sync state."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B4 DNS DHCP"
$Severity       = "P1"
$Recommendation = "All DHCP scopes that serve VDI / production should be in a failover relationship. Mode=LoadBalance for split workload; Hot Standby with 5% reserve is appropriate for branch sites. Out-of-sync state = re-init via Invoke-DhcpServerv4FailoverReplication."

if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
    [pscustomobject]@{ Note='DhcpServer module unavailable.' }; return
}
$servers = @()
if ($Global:DHCPServerList) { $servers = @($Global:DHCPServerList) }
else { try { $servers = @((Get-DhcpServerInDC -ErrorAction Stop).DnsName) } catch { } }
if ($servers.Count -eq 0) {
    [pscustomobject]@{ Note='No DHCP servers known.' }; return
}

$rendered = $false
foreach ($s in $servers) {
    if (-not $s) { continue }
    try {
        $rels = @(Get-DhcpServerv4Failover -ComputerName $s -ErrorAction Stop)
        foreach ($r in $rels) {
            $rendered = $true
            [pscustomobject]@{
                ServerA     = $r.PrimaryServerName
                ServerB     = $r.PartnerServer
                Relationship = $r.Name
                Mode        = $r.Mode
                State       = $r.State
                Scopes      = (@($r.ScopeId) -join ', ')
                MaxClientLeadTime = $r.MaxClientLeadTime
                StateSwitchInterval = $r.StateSwitchInterval
                LoadBalancePercent = $r.LoadBalancePercent
            }
        }
    } catch { }
}
if (-not $rendered) {
    [pscustomobject]@{ Note='No failover relationships configured (single point of failure for DHCP).' }
}

$TableFormat = @{
    State = { param($v,$row) if ($v -eq 'Normal') { 'ok' } elseif ($v -match 'partner-down|recover|comm-int') { 'bad' } elseif ($v) { 'warn' } else { '' } }
}
