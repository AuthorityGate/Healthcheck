# Start of Settings
# End of Settings

$Title          = 'ESXi Memory Reliability'
$Header         = 'Per-host overall memory health status (every host listed)'
$Comments       = 'Reference: KB 1003322. ESXi retires bad memory pages and exposes per-DIMM status via the hardware health system. High retire counts or non-Green memory sensors indicate failing DIMMs that need replacement. Lists every host so the absence of findings is verifiable; rows with non-green sensors include per-DIMM detail.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.2
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "If a row shows non-green status: replace the affected DIMM during the next maintenance window. Use the host's vendor BMC (iDRAC/iLO/CIMC) to identify the physical slot from the sensor name."

if (-not $Global:VCConnected) { return }

$hosts = @(Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Note='Get-VMHost returned no hosts.' }
    return
}

foreach ($h in $hosts) {
    if ($h.ConnectionState -ne 'Connected') {
        [pscustomobject]@{ Host=$h.Name; Cluster=if ($h.Parent) { "$($h.Parent.Name)" } else { '' }; DIMMCount=''; NonGreenCount=''; Status='SKIPPED (disconnected)' }
        continue
    }
    $memInfo = $null
    try { $memInfo = $h.ExtensionData.Runtime.HealthSystemRuntime.HardwareStatusInfo.MemoryStatusInfo } catch { }
    $sensors = @()
    try {
        $sensors = @($h.ExtensionData.Runtime.HealthSystemRuntime.SystemHealthInfo.NumericSensorInfo |
            Where-Object { $_.SensorType -eq 'memory' })
    } catch { }

    $dimmCount = if ($memInfo) { @($memInfo).Count } else { 0 }
    $nonGreenDIMMs = @($memInfo | Where-Object { $_.Status -and $_.Status.Key -and $_.Status.Key -ne 'green' })
    $nonGreenSensors = @($sensors | Where-Object { $_.HealthState -and $_.HealthState.Key -and $_.HealthState.Key -ne 'green' })
    $totalNonGreen = @($nonGreenDIMMs).Count + @($nonGreenSensors).Count

    if ($totalNonGreen -eq 0) {
        [pscustomobject]@{
            Host          = $h.Name
            Cluster       = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
            DIMMCount     = $dimmCount
            SensorCount   = @($sensors).Count
            NonGreenCount = 0
            Detail        = ''
            Status        = if ($dimmCount -eq 0 -and @($sensors).Count -eq 0) { 'NO HEALTH DATA' } else { 'OK (all green)' }
        }
        continue
    }

    foreach ($m in $nonGreenDIMMs) {
        $statusKey = if ($m.Status -and $m.Status.Key) { "$($m.Status.Key)" } else { 'unknown' }
        [pscustomobject]@{
            Host          = $h.Name
            Cluster       = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
            DIMMCount     = $dimmCount
            SensorCount   = @($sensors).Count
            NonGreenCount = $totalNonGreen
            Detail        = "DIMM $($m.Name) = $statusKey"
            Status        = if ($statusKey -eq 'red') { 'BAD (red)' } elseif ($statusKey -eq 'yellow') { 'WARN (yellow)' } else { "REVIEW ($statusKey)" }
        }
    }
    foreach ($s in $nonGreenSensors) {
        $statusKey = if ($s.HealthState -and $s.HealthState.Key) { "$($s.HealthState.Key)" } else { 'unknown' }
        [pscustomobject]@{
            Host          = $h.Name
            Cluster       = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
            DIMMCount     = $dimmCount
            SensorCount   = @($sensors).Count
            NonGreenCount = $totalNonGreen
            Detail        = "Sensor $($s.Name) = $statusKey"
            Status        = if ($statusKey -eq 'red') { 'BAD (red)' } elseif ($statusKey -eq 'yellow') { 'WARN (yellow)' } else { "REVIEW ($statusKey)" }
        }
    }
}

$TableFormat = @{
    Status        = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'BAD') { 'bad' } elseif ("$v" -match 'WARN|REVIEW|NO HEALTH|SKIP') { 'warn' } else { '' } }
    NonGreenCount = { param($v,$row) if ("$v" -match '^\d+$' -and [int]"$v" -gt 0) { 'warn' } else { '' } }
}
