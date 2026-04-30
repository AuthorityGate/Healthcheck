# Start of Settings
# End of Settings

$Title          = 'Host Datastore Mount Inventory'
$Header         = 'Per-host datastore mount inventory'
$Comments       = "Each host's mounted datastores (VMFS, NFS, vSAN). Mount count drift across a cluster is a cause of HA isolation responses."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'Info'
$Recommendation = 'All hosts in a cluster should mount the same datastores.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    foreach ($ds in (Get-Datastore -VMHost $h -ErrorAction SilentlyContinue)) {
        [pscustomobject]@{
            Host       = $h.Name
            Datastore  = $ds.Name
            Type       = $ds.Type
            CapacityGB = [math]::Round($ds.CapacityGB,1)
            FreeGB     = [math]::Round($ds.FreeSpaceGB,1)
        }
    }
}
