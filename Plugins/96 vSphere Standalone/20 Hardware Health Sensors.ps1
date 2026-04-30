# Start of Settings
# End of Settings

$Title          = "Hardware Health Sensors (red / yellow)"
$Header         = "Per-host hardware sensor count + non-green detail (every host listed)"
$Comments       = "vSphere queries IPMI/CIM hardware sensors per host (PSU, fans, temperature, memory, storage). Red sensors usually correlate with HW alarms in vCenter. Reference: KB 2074907. Lists every host so the audit is verifiable - hosts with all-green sensors get an OK row; non-green sensors get individual rows with detail."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P1"
$Recommendation = "Inspect each red sensor in Host -> Monitor -> Hardware Health. For PSU/fan: schedule a maintenance-mode replacement. For 'memory' or 'CPU': open a vendor case before the host fails."

if (-not $Global:VCConnected) { return }
$hosts = @(Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Note='Get-VMHost returned no hosts.' }
    return
}

foreach ($h in $hosts) {
    if ($h.ConnectionState -ne 'Connected') {
        [pscustomobject]@{ Host=$h.Name; Cluster=if ($h.Parent) {"$($h.Parent.Name)"} else {''}; Sensor=''; Status=''; Summary=''; OverallStatus='SKIPPED (disconnected)' }
        continue
    }
    $hs = $null
    try { $hs = $h.ExtensionData.Runtime.HealthSystemRuntime } catch { }
    if (-not $hs) {
        [pscustomobject]@{ Host=$h.Name; Cluster=if ($h.Parent) {"$($h.Parent.Name)"} else {''}; Sensor=''; Status=''; Summary=''; OverallStatus='NO HEALTH DATA RETURNED' }
        continue
    }
    $sensors = @()
    if ($hs.HardwareStatusInfo) {
        if ($hs.HardwareStatusInfo.MemoryStatusInfo)  { $sensors += $hs.HardwareStatusInfo.MemoryStatusInfo }
        if ($hs.HardwareStatusInfo.CpuStatusInfo)     { $sensors += $hs.HardwareStatusInfo.CpuStatusInfo }
        if ($hs.HardwareStatusInfo.StorageStatusInfo) { $sensors += $hs.HardwareStatusInfo.StorageStatusInfo }
    }
    if ($hs.SystemHealthInfo -and $hs.SystemHealthInfo.NumericSensorInfo) { $sensors += $hs.SystemHealthInfo.NumericSensorInfo }

    $sensorCount = @($sensors).Count
    $nonGreen = @($sensors | Where-Object { $_ -and ((($_.Status -and $_.Status.Key) -and $_.Status.Key -ne 'green') -or (($_.HealthState -and $_.HealthState.Key) -and $_.HealthState.Key -ne 'green')) })

    if ($nonGreen.Count -eq 0) {
        [pscustomobject]@{
            Host          = $h.Name
            Cluster       = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
            Sensor        = "$sensorCount sensors"
            Status        = 'green'
            Summary       = ''
            OverallStatus = 'OK (all green)'
        }
        continue
    }
    foreach ($s in $nonGreen) {
        $color = if ($s.Status -and $s.Status.Key) { "$($s.Status.Key)" } elseif ($s.HealthState -and $s.HealthState.Key) { "$($s.HealthState.Key)" } else { 'unknown' }
        $summary = if ($s.Status -and $s.Status.Summary) { "$($s.Status.Summary)" } elseif ($s.HealthState -and $s.HealthState.Summary) { "$($s.HealthState.Summary)" } else { '' }
        [pscustomobject]@{
            Host          = $h.Name
            Cluster       = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
            Sensor        = "$($s.Name)"
            Status        = $color
            Summary       = $summary
            OverallStatus = if ($color -eq 'red') { 'BAD' } elseif ($color -eq 'yellow') { 'WARN' } else { 'REVIEW' }
        }
    }
}

$TableFormat = @{
    Status        = { param($v,$row) if ("$v" -eq 'red') { 'bad' } elseif ("$v" -eq 'yellow') { 'warn' } elseif ("$v" -eq 'green') { 'ok' } else { '' } }
    OverallStatus = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match '^BAD|NO HEALTH') { 'bad' } elseif ("$v" -match '^WARN|REVIEW|SKIP') { 'warn' } else { '' } }
}
