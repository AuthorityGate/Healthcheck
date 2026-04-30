# Start of Settings
$MaxDevicesEnumerated = 500
# End of Settings

$Title          = "UEM Device Inventory Summary"
$Header         = "Device count by platform / enrollment status / compliance state"
$Comments       = "Aggregate view of every enrolled device. Per-platform breakdown (iOS / Android / Windows / macOS / etc.), enrollment-state distribution, compliance-state distribution. The 'is the fleet healthy' single-pane-of-glass view."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B6 Workspace ONE UEM"
$Severity       = "Info"
$Recommendation = "Sustained > 5% non-compliant fleet usually means a profile-deployment failure or a stale compliance rule. Drill into the Smart Group attached to each non-compliant device's OG."

if (-not (Get-UEMRestSession)) { return }
$resp = Get-UEMDevice
if (-not $resp -or -not $resp.Devices) {
    [pscustomobject]@{ Note = 'No devices visible to this admin scope.' }
    return
}

$devices = @($resp.Devices)
if ($devices.Count -gt $MaxDevicesEnumerated) { $devices = $devices | Select-Object -First $MaxDevicesEnumerated }

$rows = New-Object System.Collections.ArrayList
[void]$rows.Add([pscustomobject]@{ Section='Total'; Bucket='Visible Devices'; Count=$resp.Total })

# By platform
foreach ($g in ($devices | Group-Object Platform | Sort-Object Count -Descending)) {
    [void]$rows.Add([pscustomobject]@{ Section='Platform'; Bucket=$g.Name; Count=$g.Count })
}
# By enrollment status
foreach ($g in ($devices | Group-Object EnrollmentStatus | Sort-Object Count -Descending)) {
    [void]$rows.Add([pscustomobject]@{ Section='Enrollment'; Bucket=$g.Name; Count=$g.Count })
}
# By compliance status
foreach ($g in ($devices | Group-Object ComplianceStatus | Sort-Object Count -Descending)) {
    [void]$rows.Add([pscustomobject]@{ Section='Compliance'; Bucket=$g.Name; Count=$g.Count })
}
# By managed-by (UEM-fully managed vs BYOD vs Shared)
foreach ($g in ($devices | Group-Object Ownership | Sort-Object Count -Descending)) {
    [void]$rows.Add([pscustomobject]@{ Section='Ownership'; Bucket=$g.Name; Count=$g.Count })
}
$rows

$TableFormat = @{
    Bucket = { param($v,$row)
        if ($v -match 'NonCompliant|Unenrolled|Wiped') { 'bad' }
        elseif ($v -match 'Compliant|Enrolled') { 'ok' }
        elseif ($v -match 'PendingInvestigation|InCompliance') { 'warn' }
        else { '' }
    }
}
