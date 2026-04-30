# Start of Settings
# End of Settings

$Title          = 'VMFS5 Datastores Remaining (deprecated)'
$Header         = '[count] datastore(s) still on VMFS5'
$Comments       = "VMFS5 was deprecated in vSphere 6.7. VMFS6 supports automatic UNMAP, larger files (>2TB), 4K Native disk, and improved metadata locking. New 7.0/8.0 features assume VMFS6."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = "Plan migration: Storage vMotion VMs off the VMFS5 datastore, unmount/remove the VMFS5 LUN, re-format as VMFS6, mount, restore VMs. There is no in-place VMFS5->VMFS6 upgrade path."

if (-not $Global:VCConnected) { return }

foreach ($ds in (Get-Datastore -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'VMFS' } | Sort-Object Name)) {
    try {
        $ver = $ds.FileSystemVersion
        if ($ver -and $ver -notmatch '^6') {
            [pscustomobject]@{
                Datastore   = $ds.Name
                Version     = $ver
                CapacityGB  = [math]::Round($ds.CapacityGB,1)
                FreeGB      = [math]::Round($ds.FreeSpaceGB,1)
                Datacenter  = if ($ds.Datacenter) { $ds.Datacenter.Name } else { '' }
            }
        }
    } catch { }
}

$TableFormat = @{
    Version = { param($v,$row) 'warn' }
}
