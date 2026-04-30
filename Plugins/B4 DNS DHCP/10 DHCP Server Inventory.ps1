# Start of Settings
# Operator override: $Global:DHCPServerList = @('dhcp1.fqdn').
# Otherwise auto-discover via Get-DhcpServerInDC.
# End of Settings

$Title          = "DHCP Server Inventory"
$Header         = "[count] authorized DHCP server(s) in the directory"
$Comments       = "Every DHCP server registered in AD (or operator-supplied), with version, scope count, total leases. The first row to inspect when 'devices stop getting an IP' tickets land."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B4 DNS DHCP"
$Severity       = "Info"
$Recommendation = "Servers in AD but not responding indicate a service-down outage. Verify each server is current on Windows Server patches (DHCP service has had multiple CVEs)."

if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
    [pscustomobject]@{ Note='DhcpServer PowerShell module unavailable. Install via: Add-WindowsCapability -Online -Name "Rsat.DHCP.Tools~~~~0.0.1.0".' }
    return
}

$servers = @()
if ($Global:DHCPServerList) { $servers = @($Global:DHCPServerList) }
else {
    try { $servers = @((Get-DhcpServerInDC -ErrorAction Stop).DnsName) } catch { }
}
if ($servers.Count -eq 0) {
    [pscustomobject]@{ Note='No DHCP servers known. Set $Global:DHCPServerList in the runner OR install the DhcpServer module so we can auto-discover via Get-DhcpServerInDC.' }
    return
}

foreach ($s in $servers) {
    if (-not $s) { continue }
    try {
        $version = Get-DhcpServerVersion -ComputerName $s -ErrorAction Stop
        $scopes = @(Get-DhcpServerv4Scope -ComputerName $s -ErrorAction SilentlyContinue)
        $totalLeases = 0
        foreach ($sc in $scopes) {
            try { $totalLeases += @(Get-DhcpServerv4Lease -ComputerName $s -ScopeId $sc.ScopeId -ErrorAction SilentlyContinue).Count } catch { }
        }
        [pscustomobject]@{
            Server      = $s
            MajorVer    = $version.MajorVersion
            MinorVer    = $version.MinorVersion
            ScopeCount  = $scopes.Count
            ActiveLeases = $totalLeases
            DatabaseBackupPath = (Get-DhcpServerDatabase -ComputerName $s -ErrorAction SilentlyContinue).BackupPath
            BackupInterval     = (Get-DhcpServerDatabase -ComputerName $s -ErrorAction SilentlyContinue).BackupInterval
        }
    } catch {
        [pscustomobject]@{ Server=$s; MajorVer=''; MinorVer=''; ScopeCount=''; ActiveLeases=''; DatabaseBackupPath=''; BackupInterval=$_.Exception.Message }
    }
}
