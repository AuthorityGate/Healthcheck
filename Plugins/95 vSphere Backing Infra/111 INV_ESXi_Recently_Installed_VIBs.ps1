# Start of Settings
# End of Settings

$Title          = 'ESXi Recently Installed VIBs'
$Header         = 'Last 20 VIBs installed per host'
$Comments       = 'Most recently installed VIBs (patches, drivers, third-party agents) per host. Useful for change auditing and confirming a patch landed where expected.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'Info'
$Recommendation = 'Cross-reference VIB IDs with VMware patch catalog to confirm intended state.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    try {
        $esx = Get-EsxCli -VMHost $h -V2 -ErrorAction SilentlyContinue
        if (-not $esx) { return }
        $vibs = $esx.software.vib.list.Invoke() | Sort-Object @{e={[datetime]$_.InstallDate};Descending=$true} | Select-Object -First 5
        foreach ($v in $vibs) {
            [pscustomobject]@{
                Host        = $h.Name
                VibName     = $v.Name
                VibVersion  = $v.Version
                Vendor      = $v.Vendor
                AcceptanceLevel = $v.AcceptanceLevel
                InstallDate = $v.InstallDate
            }
        }
    } catch { }
}
