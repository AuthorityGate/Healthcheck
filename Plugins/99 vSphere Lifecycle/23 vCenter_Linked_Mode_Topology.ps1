# Start of Settings
# End of Settings

$Title          = 'vCenter Enhanced Linked Mode Topology'
$Header         = '[count] vCenter peer(s) in the SSO domain'
$Comments       = "Enhanced Linked Mode (ELM) replicates SSO config between vCenter peers. ELM rings of > 5 nodes get fragile; > 8 is unsupported. Replication latency between sites can introduce stale RBAC. Check that all peers are reachable and replication isn't stuck."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P3'
$Recommendation = 'Audit ELM via cmsso-util on the appliance: cmsso-util find-replication-status. Confirm <= 5 nodes per SSO domain unless a documented exception applies.'

if (-not $Global:VCConnected) { return }

# PowerCLI's `Get-VIServer -ErrorAction SilentlyContinue` errors with
# "missing mandatory parameters: Server" on some builds, so we read the
# global PowerCLI session collection directly.
$servers = @($global:DefaultVIServers | Where-Object { $_ -and $_.IsConnected })
if ($servers.Count -eq 0 -and $Global:VCServer) { $servers = @([pscustomobject]@{ Name = $Global:VCServer }) }
foreach ($srv in $servers) {
    try {
        $si = Get-View 'ServiceInstance' -Server $srv -ErrorAction Stop
        $about = $si.Content.About
        [pscustomobject]@{
            vCenter      = $srv.Name
            Version      = $about.Version
            Build        = $about.Build
            Product      = $about.Name
            ApiType      = $about.ApiType
            InstanceUuid = $si.Content.About.InstanceUuid
            Note         = 'ELM peer enumeration via cmsso-util on each appliance: ssh root@vc and run /usr/lib/vmware-vmdir/bin/vdcrepadmin -f showpartners -h localhost -u Administrator'
        }
    } catch {
        [pscustomobject]@{ vCenter=$srv.Name; Version=''; Build=''; Product=''; ApiType=''; InstanceUuid=''; Note="ServiceInstance lookup failed: $($_.Exception.Message)" }
    }
}
