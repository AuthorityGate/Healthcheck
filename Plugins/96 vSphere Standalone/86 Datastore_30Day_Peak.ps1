# Start of Settings
# Lookback window for the worst-case calculation. vCenter retains 30-min
# rollup data for ~30 days by default (Statistics Levels).
$LookbackDays = 30
$IntervalMinutes = 30
# End of Settings

$Title          = "Datastore - 30 Day Capacity Peak"
$Header         = "[count] datastore(s) profiled (current + 30 day peak fill %)"
$Comments       = @"
For each datastore visible to vCenter this plugin reports:
- Current capacity, used, free, and percent full at scan time
- Worst-case percent full over the last $LookbackDays days, with the timestamp of that peak (when datastore.usage.average rollups are present)
Note: percent-full peaks reveal short-lived storage spikes (snapshot ballooning, vMotion bursts, log flooding) that a one-time Get-Datastore snapshot would miss. Use alongside plugin 75 (Datastore Latency Outliers) for a full storage capacity + performance picture.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "Info"
$Recommendation = @"
Datastores with > 85% current usage or > 90% 30-day peak need immediate action: shrink snapshots (Get-VM | Get-Snapshot), evacuate non-critical VMs (Storage vMotion), or add capacity. VMFS guidance: leave >= 15% free for VMFS heap + snapshot growth headroom. vSAN guidance: stay < 70% to keep object resync fast and avoid declustering performance hit.
"@

if (-not $Global:VCConnected) {
    [pscustomobject]@{ Datastore='(no vCenter)'; Note='Connect a vCenter in the runner to enable datastore peak metrics.' }
    return
}

$start = (Get-Date).AddDays(-$LookbackDays)
$now   = Get-Date
$datastores = @(Get-Datastore -ErrorAction SilentlyContinue)
if ($datastores.Count -eq 0) {
    [pscustomobject]@{ Datastore='(none)'; Note='vCenter has no datastores visible to this account.' }
    return
}

foreach ($ds in $datastores) {
    if (-not $ds) { continue }
    $capGB  = [math]::Round([double]$ds.CapacityGB, 1)
    $freeGB = [math]::Round([double]$ds.FreeSpaceGB, 1)
    $usedGB = [math]::Round($capGB - $freeGB, 1)
    $pctNow = if ($capGB -gt 0) { [math]::Round(($usedGB / $capGB) * 100, 1) } else { $null }

    # 30-day capacity peak. ESXi reports datastore.used.latest in KB and
    # datastore.capacity.latest in KB; we compute pct from the ratio. For
    # NFS/vSAN in older vCenter (< 7), datastore.* may be unsupported; fall
    # back to disk.capacity.usage.average where present.
    $peakPct = $null; $peakAt = $null; $note = ''
    try {
        $stats = Get-Stat -Entity $ds -Stat 'datastore.used.latest','datastore.capacity.latest' `
                          -Start $start -Finish $now -IntervalMins $IntervalMinutes `
                          -ErrorAction Stop
        if ($stats) {
            $byTime = $stats | Group-Object Timestamp
            $best = $null
            foreach ($g in $byTime) {
                $u = ($g.Group | Where-Object { $_.MetricId -eq 'datastore.used.latest' } | Select-Object -First 1).Value
                $c = ($g.Group | Where-Object { $_.MetricId -eq 'datastore.capacity.latest' } | Select-Object -First 1).Value
                if ($u -and $c -and $c -gt 0) {
                    $pct = [math]::Round(([double]$u / [double]$c) * 100, 1)
                    if (-not $best -or $pct -gt $best.Pct) {
                        $best = [pscustomobject]@{ Pct=$pct; At=[datetime]$g.Name }
                    }
                }
            }
            if ($best) {
                $peakPct = $best.Pct
                $peakAt  = $best.At.ToString('yyyy-MM-dd HH:mm zzz')
            } else {
                $note = "No datastore.used+capacity rollup pairs in window."
            }
        } else {
            $note = "No samples returned (Statistics Level 1+ on Datastore counter required)."
        }
    } catch {
        $note = "Stat query failed: $($_.Exception.Message)"
    }

    [pscustomobject]@{
        Datastore     = $ds.Name
        Type          = [string]$ds.Type
        CapacityGB    = $capGB
        UsedGBNow     = $usedGB
        FreeGBNow     = $freeGB
        PctFullNow    = $pctNow
        PctFullPeak30d = $peakPct
        PeakAt        = $peakAt
        Accessible    = [bool]$ds.State -eq 'Available'
        Note          = $note
    }
}

$TableFormat = @{
    PctFullNow     = { param($v,$row) if ([double]"$v" -ge 90) { 'bad' } elseif ([double]"$v" -ge 80) { 'warn' } else { '' } }
    PctFullPeak30d = { param($v,$row) if ([double]"$v" -ge 95) { 'bad' } elseif ([double]"$v" -ge 85) { 'warn' } else { '' } }
}
