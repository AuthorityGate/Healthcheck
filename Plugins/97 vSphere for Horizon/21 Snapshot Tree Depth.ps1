# Start of Settings
$MaxRendered = 500
$DepthWarn = 3
$DepthBad  = 5
$AgeWarnDays = 14
# End of Settings

$Title          = "VM Snapshot Tree Depth"
$Header         = "[count] VM(s) with snapshot trees deeper than $DepthWarn"
$Comments       = "Snapshot trees deeper than 3 levels degrade VM performance and complicate consolidation. Horizon parent VMs commonly accumulate this in image-update workflows where someone forgot to consolidate after a rollback."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P2"
$Recommendation = "Consolidate snapshots > 3 deep with a maintenance window: VM -> Snapshot -> Consolidate. Old snapshots > 14 days inflate datastore usage; if it's a 'rollback safety' net, document the policy."

if (-not $Global:VCConnected) { return }

$cutoff = (Get-Date).AddDays(-$AgeWarnDays)
$rendered = 0
foreach ($vm in (Get-VM -ErrorAction SilentlyContinue)) {
    if (-not $vm) { continue }
    if ($rendered -ge $MaxRendered) { break }
    $snaps = @(Get-Snapshot -VM $vm -ErrorAction SilentlyContinue)
    if ($snaps.Count -eq 0) { continue }
    # Compute tree depth: walk parent chain of deepest snapshot
    $maxDepth = 0
    $oldestSnap = ($snaps | Sort-Object Created | Select-Object -First 1).Created
    foreach ($s in $snaps) {
        $d = 1
        $cur = $s
        while ($cur.ParentSnapshot) { $d++; $cur = $cur.ParentSnapshot }
        if ($d -gt $maxDepth) { $maxDepth = $d }
    }
    if ($maxDepth -le 1 -and ((Get-Date) - $oldestSnap).TotalDays -lt $AgeWarnDays) { continue }
    [pscustomobject]@{
        VM         = $vm.Name
        SnapshotCount = $snaps.Count
        MaxDepth   = $maxDepth
        OldestDays = [int]((Get-Date) - $oldestSnap).TotalDays
        TotalSizeGB = [math]::Round((($snaps | Measure-Object SizeGB -Sum).Sum), 2)
    }
    $rendered++
}
if ($rendered -eq 0) {
    [pscustomobject]@{ Note = 'No problematic snapshot trees (all snapshots <= depth 1 and < 14 days old).' }
}

$TableFormat = @{
    MaxDepth   = { param($v,$row) if ([int]"$v" -gt $DepthBad) { 'bad' } elseif ([int]"$v" -gt $DepthWarn) { 'warn' } else { '' } }
    OldestDays = { param($v,$row) if ([int]"$v" -gt 30) { 'warn' } else { '' } }
}
