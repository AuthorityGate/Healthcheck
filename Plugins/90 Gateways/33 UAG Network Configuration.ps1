# Start of Settings
# End of Settings

$Title          = "UAG Network Configuration"
$Header         = "UAG NIC, IP, route, DNS, NTP"
$Comments       = "Networking baseline for the UAG appliance. Misconfigured DNS / NTP is the silent root cause for Kerberos brittleness and broker-trust failures."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "90 Gateways"
$Severity       = "Info"
$Recommendation = "Two-NIC topology (eth0=Internet/DMZ; eth1=internal LAN) is the supported pattern. NTP must point at the same time source as the broker + DCs (cert auth fails on > 5 min skew)."

if (-not (Get-UAGRestSession)) { return }
$rows = @()
try { $nic = Get-UAGNICs } catch { }
try { $rt  = Get-UAGRoute } catch { }
try { $dns = Get-UAGDNS } catch { }
try { $ntp = Get-UAGNTP } catch { }

foreach ($n in @($nic)) {
    if (-not $n) { continue }
    $rows += [pscustomobject]@{ Type='NIC'; Name=$n.name; Value=("$($n.ipv4Address)/$($n.ipv4Prefix) gw=$($n.ipv4DefaultGateway)") }
}
foreach ($r in @($rt)) {
    if (-not $r) { continue }
    $rows += [pscustomobject]@{ Type='Route'; Name=$r.cidr; Value="via $($r.gateway) on $($r.nic)" }
}
if ($dns) {
    $rows += [pscustomobject]@{ Type='DNS'; Name='Servers'; Value=($dns.servers -join ', ') }
    $rows += [pscustomobject]@{ Type='DNS'; Name='Search';  Value=($dns.searchDomains -join ', ') }
}
if ($ntp) {
    $rows += [pscustomobject]@{ Type='NTP'; Name='Servers'; Value=($ntp.servers -join ', ') }
}
if (-not $rows -or $rows.Count -eq 0) {
    [pscustomobject]@{ Note = 'No network details returned (auth role may lack /config/system/network access).' }
    return
}
$rows
