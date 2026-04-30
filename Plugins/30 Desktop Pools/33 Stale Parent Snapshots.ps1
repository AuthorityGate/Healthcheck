# Start of Settings
# Snapshot age threshold (days). Parent VM snapshots older than this trigger a finding.
$SnapshotAgeDays = 30
# End of Settings

$Title          = "Stale Parent VM Snapshots"
$Header         = "[count] pool(s) using a parent snapshot older than $SnapshotAgeDays days"
$Comments       = "Instant-clone and linked-clone pools using stale parent snapshots accumulate Windows updates / agent versions out of band. Re-publish on a regular cadence."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "30 Desktop Pools"
$Severity       = "P2"
$Recommendation = "Patch the parent VM, take a new snapshot, and run 'Push Image' / 'Schedule Image' for each affected pool."

$pools = Get-HVDesktopPool
if (-not $pools) { return }
if (-not $Global:VCConnected) {
    Write-Verbose "vCenter not connected; skipping snapshot age check."
    return
}

$cutoff = (Get-Date).AddDays(-$SnapshotAgeDays)

foreach ($p in $pools) {
    $parent   = $null
    $snap     = $null
    if ($p.provisioning_settings -and $p.provisioning_settings.parent_vm_id) {
        $parent = $p.provisioning_settings.parent_vm_path
        $snap   = $p.provisioning_settings.snapshot_path
    } elseif ($p.source -eq 'INSTANT_CLONE_ENGINE' -and $p.instant_clone_engine_provisioning_settings) {
        $parent = $p.instant_clone_engine_provisioning_settings.parent_vm_path
        $snap   = $p.instant_clone_engine_provisioning_settings.snapshot_path
    }
    if (-not $parent) { continue }

    $vmShortName = ($parent -split '/')[-1]
    $snapName    = if ($snap) { ($snap -split '/')[-1] } else { $null }

    try {
        $vm = Get-VM -Name $vmShortName -ErrorAction Stop
    } catch { continue }

    $s = if ($snapName) { Get-Snapshot -VM $vm -Name $snapName -ErrorAction SilentlyContinue } else {
            Get-Snapshot -VM $vm -ErrorAction SilentlyContinue | Sort-Object Created -Descending | Select-Object -First 1
         }
    if (-not $s) { continue }

    if ($s.Created -lt $cutoff) {
        [pscustomobject]@{
            Pool         = $p.name
            ParentVM     = $vmShortName
            Snapshot     = $s.Name
            SnapshotDate = $s.Created
            AgeDays      = [int]((Get-Date) - $s.Created).TotalDays
        }
    }
}

$TableFormat = @{
    AgeDays = { param($v,$row) if ([int]$v -gt 60) { 'bad' } elseif ([int]$v -gt 30) { 'warn' } else { '' } }
}
