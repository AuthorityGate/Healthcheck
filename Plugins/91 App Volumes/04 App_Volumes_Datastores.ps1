# Start of Settings
# End of Settings

$Title          = 'App Volumes Datastores'
$Header         = '[count] datastore(s) registered for AppStacks / Writables'
$Comments       = "Reference: 'Storage Configuration' (App Volumes docs). Datastores must be reachable from every host in the AV-managed cluster."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P2'
$Recommendation = 'Decommission datastores no longer accessible. Confirm each is mounted on every host.'

if (-not (Get-AVRestSession)) { return }
$ds = Get-AVDatastore
if (-not $ds) { return }
foreach ($d in $ds.datastores) {
    [pscustomobject]@{
        Name         = $d.name
        Datacenter   = $d.datacenter
        CapacityGB   = [math]::Round($d.capacity / 1GB, 1)
        FreeGB       = [math]::Round($d.free_space / 1GB, 1)
        Type         = $d.template_storage
        Accessible   = $d.accessible
        Note         = $d.note
    }
}
