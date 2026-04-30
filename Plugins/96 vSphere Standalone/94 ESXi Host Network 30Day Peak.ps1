# Start of Settings
$LookbackDays = 30
$IntervalMinutes = 30
# End of Settings

$Title          = "ESXi Host Network - 30 Day Peak"
$Header         = "[count] host(s) profiled for network throughput peak"
$Comments       = "Per-host aggregate network throughput peak (transmit + receive) over the last $LookbackDays days, with timestamp. Used to size NIC uplinks and identify chatty hosts."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "Info"
$Recommendation = "Hosts whose 30-day peak approaches NIC line rate (e.g., 8+ Gbps on a 10 GbE link) need either link aggregation, 25 GbE upgrade, or workload rebalancing."

if (-not $Global:VCConnected) { return }
$start = (Get-Date).AddDays(-$LookbackDays); $now = Get-Date
foreach ($h in @(Get-VMHost -ErrorAction SilentlyContinue)) {
    if (-not $h) { continue }
    $txMb = $null; $txAt = $null; $rxMb = $null; $rxAt = $null; $note = ''
    try {
        $stats = Get-Stat -Entity $h -Stat 'net.transmitted.average','net.received.average' `
                          -Start $start -Finish $now -IntervalMins $IntervalMinutes `
                          -ErrorAction Stop
        if ($stats) {
            $tx = $stats | Where-Object { $_.MetricId -eq 'net.transmitted.average' -and $_.Instance -eq '' }
            $rx = $stats | Where-Object { $_.MetricId -eq 'net.received.average' -and $_.Instance -eq '' }
            $tt = $tx | Sort-Object Value -Descending | Select-Object -First 1
            $rt = $rx | Sort-Object Value -Descending | Select-Object -First 1
            if ($tt) { $txMb = [math]::Round([double]$tt.Value / 1024, 1); $txAt = $tt.Timestamp.ToString('yyyy-MM-dd HH:mm zzz') }
            if ($rt) { $rxMb = [math]::Round([double]$rt.Value / 1024, 1); $rxAt = $rt.Timestamp.ToString('yyyy-MM-dd HH:mm zzz') }
        }
    } catch { $note = $_.Exception.Message }
    [pscustomobject]@{
        Host          = $h.Name
        TxPeakMBps    = $txMb
        TxPeakAt      = $txAt
        RxPeakMBps    = $rxMb
        RxPeakAt      = $rxAt
        Note          = $note
    }
}
