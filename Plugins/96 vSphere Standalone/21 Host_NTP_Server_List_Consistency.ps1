# Start of Settings
# End of Settings

$Title          = 'Host NTP Server List Consistency'
$Header         = 'Per-host NTP server list (every host listed; mismatched clusters flagged)'
$Comments       = 'Mixed NTP sources within a cluster lead to subtle skew. The 95-Backing/92 ESXi NTP plugin checks that NTP is running and skew is bounded; this plugin checks that every host in a cluster points at the SAME NTP servers, in the same order. Drift here is usually the result of a manual edit on a single host that never propagated.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Apply via host profile OR PowerCLI: foreach host: Add-VMHostNtpServer + Remove-VMHostNtpServer to converge to the cluster standard list. After convergence: Set-VMHostService ntpd policy=on; Restart-VMHostService ntpd.'

if (-not $Global:VCConnected) { return }

$clusters = @(Get-Cluster -ErrorAction SilentlyContinue | Sort-Object Name)
if ($clusters.Count -eq 0) {
    [pscustomobject]@{ Note='No clusters returned by Get-Cluster.' }
    return
}

foreach ($cl in $clusters) {
    $hosts = @(Get-VMHost -Location $cl -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($hosts.Count -eq 0) {
        [pscustomobject]@{ Cluster=$cl.Name; Host=''; NtpServers=''; Status='NO HOSTS' }
        continue
    }
    $sets = @{}
    foreach ($h in $hosts) {
        $list = (@(Get-VMHostNtpServer -VMHost $h -ErrorAction SilentlyContinue) -join ',')
        $sets[$list] = $true
    }
    $clusterStatus = if (@($sets.Keys).Count -gt 1) { "MISMATCH ($(@($sets.Keys).Count) distinct NTP lists)" } else { 'OK' }

    foreach ($h in $hosts) {
        if ($h.ConnectionState -ne 'Connected') {
            [pscustomobject]@{ Cluster=$cl.Name; Host=$h.Name; NtpServers=''; ServerCount=''; Status='SKIPPED (disconnected)' }
            continue
        }
        $list = @(Get-VMHostNtpServer -VMHost $h -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            Cluster     = $cl.Name
            Host        = $h.Name
            NtpServers  = if ($list.Count -gt 0) { ($list -join ', ') } else { '(none)' }
            ServerCount = $list.Count
            Status      = $clusterStatus
        }
    }
}

$TableFormat = @{
    NtpServers  = { param($v,$row) if ("$v" -eq '(none)') { 'bad' } else { '' } }
    ServerCount = { param($v,$row) if ("$v" -match '^\d+$' -and [int]"$v" -lt 2) { 'warn' } else { '' } }
    Status      = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -match 'MISMATCH|NO NTP|NO HOSTS') { 'warn' } else { '' } }
}
