# Start of Settings
# Snapshots older than this number of days are reported (excluding parent VMs published to Horizon - those are a separate plugin).
$SnapshotAgeDays = 14
# End of Settings

$Title          = "Old VM Snapshots (vSphere)"
$Header         = "[count] snapshot(s) older than $SnapshotAgeDays days"
$Comments       = "Long-lived snapshots cause IO penalty and consolidation problems. Parent-VM snapshots used by pools are intentionally excluded."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "95 vSphere Backing Infra"
$Severity       = "P2"
$Recommendation = "Consolidate or delete snapshots older than $SnapshotAgeDays days unless retained for a documented backup cycle."

if (-not $Global:VCConnected) { return }

# Build the parent-VM exclusion set
$parentVms = @{}
foreach ($p in (Get-HVDesktopPool)) {
    $pn = $null
    if ($p.provisioning_settings -and $p.provisioning_settings.parent_vm_path) {
        $pn = ($p.provisioning_settings.parent_vm_path -split '/')[-1]
    } elseif ($p.instant_clone_engine_provisioning_settings -and $p.instant_clone_engine_provisioning_settings.parent_vm_path) {
        $pn = ($p.instant_clone_engine_provisioning_settings.parent_vm_path -split '/')[-1]
    }
    if ($pn) { $parentVms[$pn] = $true }
}

$cutoff = (Get-Date).AddDays(-$SnapshotAgeDays)

Get-VM -ErrorAction SilentlyContinue | Where-Object { -not $parentVms.ContainsKey($_.Name) } |
    Get-Snapshot -ErrorAction SilentlyContinue |
    Where-Object { $_.Created -lt $cutoff } |
    ForEach-Object {
        [pscustomobject]@{
            VM        = $_.VM.Name
            Snapshot  = $_.Name
            Created   = $_.Created
            AgeDays   = [int]((Get-Date) - $_.Created).TotalDays
            SizeGB    = [math]::Round($_.SizeGB,2)
            Description = $_.Description
        }
    } | Sort-Object AgeDays -Descending

$TableFormat = @{
    AgeDays = { param($v,$row) if ([int]$v -gt 90) { 'bad' } elseif ([int]$v -gt 30) { 'warn' } else { '' } }
}
