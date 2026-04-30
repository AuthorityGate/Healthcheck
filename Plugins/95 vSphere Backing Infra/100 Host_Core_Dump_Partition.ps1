# Start of Settings
# End of Settings

$Title          = 'Host Core Dump Partition'
$Header         = '[count] host(s) without active core dump location'
$Comments       = 'Reference: KB 2004299. Core dumps are mandatory for VMware support cases.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = 'esxcli system coredump partition set --enable=true --partition <vmfs-uuid>:1 OR network coredump on dump collector.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $cdp = (Get-EsxCli -VMHost $_ -V2 -ErrorAction SilentlyContinue)
    if (-not $cdp) { return }
    try {
        $part = $cdp.system.coredump.partition.get.Invoke()
        if (-not $part.Active) {
            [pscustomobject]@{ Host=$_.Name; CoreDumpActive=$false; ConfiguredPartition=$part.Configured }
        }
    } catch { }
}
