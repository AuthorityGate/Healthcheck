# Start of Settings
$WarnReadMs  = 25
$BadReadMs   = 50
$WarnWriteMs = 25
$BadWriteMs  = 50
$SampleMinutes = 30
# End of Settings

$Title          = 'Datastore Read/Write Latency Outliers'
$Header         = '[count] datastore(s) with read or write latency above threshold'
$Comments       = "Per-datastore avg read + write latency over the last $SampleMinutes minutes. > $WarnReadMs ms is concerning; > $BadReadMs ms is bad. KB 1008205 covers latency tuning. Latency outliers point at array-side queue depth, fabric saturation, or specific noisy VMs."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P2'
$Recommendation = 'Identify the noisy VMs via Performance -> Datastore -> esxtop u screen. Confirm storage path utilization (multipathing 05). Consider Storage DRS I/O load balancing if the array supports the metric.'

if (-not $Global:VCConnected) { return }

$end = Get-Date; $start = $end.AddMinutes(-$SampleMinutes)

foreach ($ds in (Get-Datastore -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'VMFS' } | Sort-Object Name)) {
    try {
        $stats = $null
        try {
            $stats = Get-Stat -Entity $ds -Stat 'datastore.totalReadLatency.average','datastore.totalWriteLatency.average' -Start $start -Finish $end -IntervalMins 5 -ErrorAction Stop
        } catch { }
        if (-not $stats) { continue }
        $rd = ($stats | Where-Object MetricId -like '*Read*' | Measure-Object -Property Value -Average).Average
        $wr = ($stats | Where-Object MetricId -like '*Write*' | Measure-Object -Property Value -Average).Average
        $rd = if ($rd) { [math]::Round($rd,1) } else { 0 }
        $wr = if ($wr) { [math]::Round($wr,1) } else { 0 }
        if ($rd -ge $WarnReadMs -or $wr -ge $WarnWriteMs) {
            [pscustomobject]@{
                Datastore   = $ds.Name
                AvgReadMs   = $rd
                AvgWriteMs  = $wr
                SampleMins  = $SampleMinutes
                CapacityGB  = [math]::Round($ds.CapacityGB,1)
            }
        }
    } catch { }
}

$TableFormat = @{
    AvgReadMs  = { param($v,$row) if ([decimal]$v -ge $BadReadMs) { 'bad' } elseif ([decimal]$v -ge $WarnReadMs) { 'warn' } else { '' } }
    AvgWriteMs = { param($v,$row) if ([decimal]$v -ge $BadWriteMs) { 'bad' } elseif ([decimal]$v -ge $WarnWriteMs) { 'warn' } else { '' } }
}
