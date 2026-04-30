# Start of Settings
# End of Settings

$Title          = 'vDS LACP Configuration'
$Header         = '[count] vDS(es) with LACP groups inventory'
$Comments       = "vSphere Distributed Switch supports LACP LAG (Link Aggregation Control Protocol) for active-active uplink bundling with hash-based load balancing. Enhanced LACP (vDS 5.5+) supports up to 64 LAGs per host. Misconfigured LACP = link flap and brokered traffic."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Coordinate with the network team: physical-switch LAG mode (active/passive), hash algorithm (L2/L3/L4), and timeout (fast/slow) must match on both sides. If LACP misconfigured, traffic blackholes silently.'

if (-not $Global:VCConnected) { return }

foreach ($vds in (Get-VDSwitch -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $vdsView = $vds | Get-View
        $lacpGroups = @($vdsView.Config.LacpGroupConfig)
        if ($lacpGroups.Count -eq 0) {
            [pscustomobject]@{
                vDS          = $vds.Name
                Version      = $vds.Version
                LACPGroups   = 0
                Note         = 'No LACP LAG configured. Active-active without LAG uses VMware load-balancing only (per-VM port-ID, IP hash, etc.).'
            }
        } else {
            foreach ($g in $lacpGroups) {
                [pscustomobject]@{
                    vDS         = $vds.Name
                    Version     = $vds.Version
                    LAGName     = $g.Name
                    Mode        = $g.Mode
                    UplinkCount = $g.UplinkNum
                    LoadBalance = $g.LoadbalanceAlgorithm
                    TimeoutMode = $g.TimeoutMode
                }
            }
        }
    } catch { }
}
