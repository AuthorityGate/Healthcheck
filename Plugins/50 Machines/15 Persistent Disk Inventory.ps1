# Start of Settings
# End of Settings

$Title          = "Persistent Disk Inventory"
$Header         = "[count] persistent disk(s) tracked by Horizon"
$Comments       = "All persistent disks (separate user data disks for full-clone pools). Used to plan upgrade cutovers - persistent disks survive pool re-provision but require explicit migration when retiring pools."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "50 Machines"
$Severity       = "Info"
$Recommendation = "Orphaned persistent disks (no owning user / no machine attached) waste storage and complicate audits. Reattach or archive."

if (-not (Get-HVRestSession)) { return }
$disks = @(Get-HVPersistentDisk)
if (-not $disks) { return }

foreach ($d in $disks) {
    [pscustomobject]@{
        Name        = $d.name
        Pool        = $d.desktop_pool_id
        UserOrGroup = $d.user_id
        Machine     = $d.machine_id
        Status      = $d.status
        Datastore   = $d.datastore_path
        SizeMB      = $d.capacity_mb
        Usable      = [bool]$d.is_usable_in_archive
    }
}

$TableFormat = @{
    Status = { param($v,$row) if ($v -eq 'IN_USE') { 'ok' } elseif ($v -in @('UNUSED','UNATTACHED','ARCHIVED')) { 'warn' } else { '' } }
}
