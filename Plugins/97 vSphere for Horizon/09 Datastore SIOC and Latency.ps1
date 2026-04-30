# Start of Settings
# Latency above this threshold is reported (avg over the last sample window).
$LatencyThresholdMs = 25
# End of Settings

$Title          = "Datastore SIOC + Latency"
$Header         = "[count] datastore(s) with SIOC disabled or with high latency"
$Comments       = "VMware Storage I/O Control (SIOC) keeps boot-storm IOPS bursts from starving other workloads. Reference: KB 1022091 + 'vSphere Resource Management - Storage I/O Control'. For Horizon: enable SIOC on every datastore that hosts replicas, full clones, or persistent disks."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P3"
$Recommendation = "Datastore -> Configure -> General -> 'Storage I/O Control' -> Enable. Set congestion threshold = 30 ms (default) unless your storage vendor publishes a different number."

if (-not $Global:VCConnected) { return }

Get-Datastore -ErrorAction SilentlyContinue | ForEach-Object {
    $ds = $_
    $sioc = $ds.StorageIOControlEnabled
    # Latency from last 5 minutes (best effort - sometimes empty on VMFS-only hosts)
    $latency = $null
    try {
        $stat = Get-Stat -Entity $ds -Stat 'datastore.totalReadLatency.average','datastore.totalWriteLatency.average' `
                  -Realtime -MaxSamples 5 -ErrorAction SilentlyContinue
        if ($stat) {
            $latency = [math]::Round((($stat | Measure-Object Value -Average).Average), 1)
        }
    } catch { }
    $bad = (-not $sioc) -or ($latency -gt $LatencyThresholdMs)
    if ($bad) {
        [pscustomobject]@{
            Datastore   = $ds.Name
            Type        = $ds.Type
            CapacityGB  = [math]::Round($ds.CapacityGB,1)
            FreeGB      = [math]::Round($ds.FreeSpaceGB,1)
            SIOC        = $sioc
            AvgLatencyMs = if ($null -ne $latency) { $latency } else { 'n/a' }
        }
    }
}

$TableFormat = @{
    SIOC          = { param($v,$row) if ($v -ne $true) { 'warn' } else { 'ok' } }
    AvgLatencyMs  = { param($v,$row) if ($v -is [double] -and $v -gt 25) { 'warn' } else { '' } }
}
