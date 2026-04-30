# Start of Settings
# End of Settings

$Title          = 'Desktop Pool Storage Placement'
$Header         = "[count] pool(s) with storage placement details"
$Comments       = "Per-pool datastore assignment - which datastore(s) each pool's clones live on. Useful for capacity planning + identifying pools sharing datastores (load contention)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '30 Desktop Pools'
$Severity       = 'Info'
$Recommendation = "Production pools should have dedicated datastores OR documented sharing strategy. Replica + delta datastore separation per Horizon best practices."

if (-not (Get-HVRestSession)) { return }

foreach ($p in (Get-HVDesktopPool)) {
    $datastores = @()
    foreach ($prop in 'provisioning_settings','instant_clone_engine_provisioning_settings','manual_settings') {
        $s = $p.$prop
        if ($s -and $s.datastores) {
            foreach ($d in @($s.datastores)) { $datastores += $d.datastore_path }
        }
        if ($s -and $s.replica_disk_datastore) { $datastores += "REPLICA: $($s.replica_disk_datastore.datastore_path)" }
    }
    [pscustomobject]@{
        Pool         = $p.display_name
        Type         = $p.type
        Datastores   = ($datastores | Sort-Object -Unique) -join '; '
        Count        = ($datastores | Sort-Object -Unique).Count
        Note         = if ($datastores.Count -eq 0) { 'No datastores configured' } else { '' }
    }
}
