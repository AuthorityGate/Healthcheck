# Start of Settings
$InterestingOptions = @(3, 6, 15, 43, 60, 66, 67, 252)
# End of Settings

$Title          = "DHCP Scope Options Audit"
$Header         = "[count] scope option(s) of interest set across servers"
$Comments       = "Per-scope option inventory of the well-known 'easy to misconfigure' DHCP options: 3 (Router), 6 (DNS), 15 (Domain), 43 (Vendor-specific - PXE/Imprivata/Wyse), 60 (Vendor Class - PXE), 66 (Boot Server / TFTP), 67 (Boot File), 252 (WPAD). Wrong values silently break PXE / kiosks / proxy auto-config."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B4 DNS DHCP"
$Severity       = "Info"
$Recommendation = "Confirm option 6 (DNS Servers) matches the AD-integrated DNS, not a stale list. Option 252 (WPAD) URLs that no longer resolve = silent web-proxy outages on every new lease."

if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
    [pscustomobject]@{ Note = 'DhcpServer module not available.' }; return
}
$servers = @()
if ($Global:DHCPServerList) { $servers = @($Global:DHCPServerList) }
else { try { $servers = @((Get-DhcpServerInDC -ErrorAction Stop).DnsName) } catch { } }
if ($servers.Count -eq 0) { return }

$rendered = 0
foreach ($s in $servers) {
    if (-not $s) { continue }
    foreach ($scope in @(Get-DhcpServerv4Scope -ComputerName $s -ErrorAction SilentlyContinue)) {
        foreach ($oid in $InterestingOptions) {
            try {
                $opt = Get-DhcpServerv4OptionValue -ComputerName $s -ScopeId $scope.ScopeId -OptionId $oid -ErrorAction SilentlyContinue
                if ($opt) {
                    [pscustomobject]@{
                        Server   = $s
                        Scope    = $scope.Name
                        OptionId = $oid
                        OptionName = $opt.Name
                        Value    = ($opt.Value -join '; ')
                    }
                    $rendered++
                }
            } catch { }
        }
    }
}
if ($rendered -eq 0) {
    [pscustomobject]@{ Note='No scope options of interest set.' }
}
