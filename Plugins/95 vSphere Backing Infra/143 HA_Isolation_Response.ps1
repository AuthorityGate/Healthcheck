# Start of Settings
# Recommended response by storage type:
#   vSAN / vVols / NFS: PowerOff (or Shutdown) so HA can restart elsewhere.
#   Block (FC/iSCSI/local): LeaveRunning may be acceptable.
$RecommendedForVsan = 'PowerOff'
# End of Settings

$Title          = 'HA Isolation Response'
$Header         = '[count] cluster(s) with isolation response not aligned to storage type'
$Comments       = "vSphere HA isolation response: when a host loses heartbeat, what does it do with running VMs? LeaveRunning (default) is wrong for vSAN / NFS - the surviving cluster cannot restart the VM elsewhere if the original host is still running it on shared storage."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = 'Cluster -> Configure -> vSphere Availability -> Edit -> Failures and Responses -> Response for Host Isolation = Power Off and restart VMs (vSAN/NFS) or Leave Powered On (block FC/iSCSI).'

if (-not $Global:VCConnected) { return }

foreach ($c in (Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.HAEnabled } | Sort-Object Name)) {
    try {
        $cv = $c | Get-View -ErrorAction Stop
        $cfg = $cv.Configuration
        $isoResp = $cfg.DasConfig.DefaultVmSettings.IsolationResponse
        $isVsan  = $c.VsanEnabled
        $issue   = $null
        if ($isVsan -and $isoResp -eq 'none') { $issue = 'vSAN cluster with LeaveRunning isolation response - VMs cannot restart elsewhere on isolation event.' }
        if ($issue) {
            [pscustomobject]@{
                Cluster          = $c.Name
                IsolationResponse= $isoResp
                StorageType      = if ($isVsan) { 'vSAN' } else { 'mixed' }
                Issue            = $issue
                Recommended      = $RecommendedForVsan
            }
        } else {
            # also surface the current value for fleet visibility
            [pscustomobject]@{
                Cluster          = $c.Name
                IsolationResponse= $isoResp
                StorageType      = if ($isVsan) { 'vSAN' } else { 'mixed' }
                Issue            = ''
                Recommended      = if ($isVsan) { $RecommendedForVsan } else { 'depends on storage' }
            }
        }
    } catch { }
}

$TableFormat = @{
    Issue = { param($v,$row) if ($v) { 'warn' } else { '' } }
}
