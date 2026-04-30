# Start of Settings
# End of Settings

$Title          = 'Host DNS Server List Consistency'
$Header         = 'Per-host DNS server list (every host listed; mismatched clusters flagged)'
$Comments       = 'Hosts with stale DNS pointing at decommissioned servers cause slow vSphere Client login + cert validation. Lists every host with its DNS resolver list and search-suffix list so operators can verify intent across the cluster, then flags clusters where hosts disagree.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Standardize DNS via host profile or PowerCLI: Get-VMHostNetwork -VMHost <h> | Set-VMHostNetwork -DnsAddress <list>. Mismatch within a cluster usually means a manual edit during a network-change event that did not propagate.'

if (-not $Global:VCConnected) { return }

$clusters = @(Get-Cluster -ErrorAction SilentlyContinue | Sort-Object Name)
if ($clusters.Count -eq 0) {
    [pscustomobject]@{ Note='No clusters returned by Get-Cluster.' }
    return
}

foreach ($cl in $clusters) {
    $hosts = @(Get-VMHost -Location $cl -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($hosts.Count -eq 0) {
        [pscustomobject]@{ Cluster=$cl.Name; Host=''; DnsServers=''; SearchDomains=''; Status='NO HOSTS' }
        continue
    }
    # First pass: build distinct-set count for the cluster status
    $sets = @{}
    foreach ($h in $hosts) {
        $cfg = $null; try { $cfg = $h.ExtensionData.Config.Network.DnsConfig } catch { }
        if (-not $cfg) { continue }
        $key = (@($cfg.Address) -join ',')
        $sets[$key] = $true
    }
    $clusterStatus = if (@($sets.Keys).Count -gt 1) { "MISMATCH ($(@($sets.Keys).Count) distinct DNS sets)" } else { 'OK' }

    foreach ($h in $hosts) {
        if ($h.ConnectionState -ne 'Connected') {
            [pscustomobject]@{ Cluster=$cl.Name; Host=$h.Name; DnsServers=''; SearchDomains=''; Status='SKIPPED (disconnected)' }
            continue
        }
        $cfg = $null; try { $cfg = $h.ExtensionData.Config.Network.DnsConfig } catch { }
        if (-not $cfg) {
            [pscustomobject]@{ Cluster=$cl.Name; Host=$h.Name; DnsServers='(unknown)'; SearchDomains=''; Status='NO DNS CONFIG' }
            continue
        }
        [pscustomobject]@{
            Cluster       = $cl.Name
            Host          = $h.Name
            DnsServers    = (@($cfg.Address) -join ', ')
            SearchDomains = (@($cfg.SearchDomain) -join ', ')
            Status        = $clusterStatus
        }
    }
}

$TableFormat = @{
    Status = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -match 'MISMATCH|NO DNS|NO HOSTS') { 'warn' } else { '' } }
}
