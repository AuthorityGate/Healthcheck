# Start of Settings
# End of Settings

$Title          = 'ESXi Hardware Sensors Detailed'
$Header         = "[count] hardware sensor(s) reporting non-green state"
$Comments       = "Per-sensor detail across the fleet (PSU, fans, temperature, voltage, ECC). Beyond the binary 'red/yellow' alarm, the specific sensor + reading helps the consultant identify which DIMM, which PSU, which fan."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P1'
$Recommendation = "Each row names one sensor on one host. Cross-reference with vendor BMC for the physical slot/component. Open hardware support case."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue)) {
    if ($h.ConnectionState -ne 'Connected') { continue }
    try {
        $hwInfo = $h.ExtensionData.Runtime.HealthSystemRuntime
        if (-not $hwInfo) { continue }

        # NumericSensorInfo - specific reading + threshold
        $sensors = $hwInfo.SystemHealthInfo.NumericSensorInfo
        foreach ($s in @($sensors | Where-Object { $_.HealthState -and $_.HealthState.Key -ne 'green' })) {
            [pscustomobject]@{
                Host = $h.Name
                Cluster = if ($h.Parent) { $h.Parent.Name } else { '' }
                SensorType = $s.SensorType
                Name = $s.Name
                CurrentReading = "$($s.CurrentReading) $($s.BaseUnits)"
                State = $s.HealthState.Key
                Description = $s.HealthState.Summary
            }
        }
    } catch { }
}

$TableFormat = @{
    State = { param($v,$row) if ($v -eq 'red') { 'bad' } elseif ($v -eq 'yellow') { 'warn' } else { '' } }
}
