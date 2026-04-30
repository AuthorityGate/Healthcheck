# Start of Settings
# End of Settings

$Title          = 'NVIDIA vGPU Host Driver / Manager Inventory'
$Header         = '[count] host(s) with NVIDIA vGPU manager (NVD VIBs)'
$Comments       = "Per-host NVIDIA host driver (NVD VIB) version. Driver currency matters: NVIDIA enforces N <-> N-1 compatibility between host driver and guest driver in vGPU mode. Drift across hosts blocks vMotion of vGPU VMs."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '97 vSphere for Horizon'
$Severity       = 'P3'
$Recommendation = 'Pin a single host driver version per cluster. Pair with a single guest driver version baked into the gold image. Update via vLCM image baseline rather than esxcli for fleet uniformity.'

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $esxcli = Get-EsxCli -V2 -VMHost $h -ErrorAction Stop
        $vibs = $esxcli.software.vib.list.Invoke()
        $nvd = @($vibs | Where-Object { $_.Vendor -match 'NVIDIA' -or $_.Name -match 'NVD' -or $_.Name -match 'nvidia' })
        foreach ($v in $nvd) {
            [pscustomobject]@{
                Host        = $h.Name
                VIBName     = $v.Name
                Version     = $v.Version
                Vendor      = $v.Vendor
                AcceptanceLevel = $v.AcceptanceLevel
                InstallDate = $v.InstallDate
            }
        }
    } catch { }
}
