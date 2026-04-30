# Start of Settings
# End of Settings

$Title          = 'ESXi Coredump Partition Health'
$Header         = "[count] host(s) with coredump partition issues"
$Comments       = "ESXi coredump destination = where the kernel writes a crash dump on PSOD. Without active coredump = no diagnostic for crash analysis. Local partition or network coredump server required."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Configure coredump per host: local partition OR network coredump server (preferred for stateless installs). Verify via 'esxcli system coredump partition list'."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue)) {
    if ($h.ConnectionState -ne 'Connected') { continue }
    try {
        $esxcli = Get-EsxCli -V2 -VMHost $h -ErrorAction Stop

        # Local partition
        $local = $esxcli.system.coredump.partition.get.Invoke()
        $localActive = if ($local -and $local.Active) { $local.Active } else { '(none)' }

        # Network destination
        $netConfigured = $false
        $netServer = ''
        try {
            $net = $esxcli.system.coredump.network.get.Invoke()
            if ($net.Enabled -eq 'true') {
                $netConfigured = $true
                $netServer = "$($net.HostVNic):$($net.NetworkServerIP):$($net.NetworkServerPort)"
            }
        } catch { }

        $isHealthy = ($localActive -ne '(none)' -and $localActive) -or $netConfigured
        if (-not $isHealthy) {
            [pscustomobject]@{
                Host = $h.Name
                Cluster = if ($h.Parent) { $h.Parent.Name } else { '' }
                LocalPartition = $localActive
                NetworkCoredump = if ($netConfigured) { $netServer } else { 'Not configured' }
                Note = 'No active coredump destination - PSOD will produce no diagnostic dump.'
            }
        }
    } catch {
        [pscustomobject]@{
            Host = $h.Name; LocalPartition = '(error)'; NetworkCoredump = ''; Note = "esxcli failed: $($_.Exception.Message)"
        }
    }
}

$TableFormat = @{
    Note = { param($v,$row) if ($v -match 'No active') { 'bad' } else { '' } }
}
