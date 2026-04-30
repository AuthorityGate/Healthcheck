# Start of Settings
# End of Settings

$Title          = 'VAAI Hardware Acceleration Per-LUN'
$Header         = "[count] LUN(s) with non-supported VAAI primitives"
$Comments       = "VAAI offloads ATS (locking), XCOPY (clone), WRITE_SAME (zero) to the storage array. Without VAAI, host CPU does the work = slow clone/zero/lock. Most modern arrays support all three; legacy may support partial."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = "All three primitives (ATS, XCOPY, WRITE_SAME) supported is the modern baseline. If unsupported on a LUN, check array firmware + ESXi VAAI plug-in. Update to enable."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue) | Select-Object -First 1) {
    if ($h.ConnectionState -ne 'Connected') { continue }
    try {
        $esxcli = Get-EsxCli -V2 -VMHost $h -ErrorAction Stop
        $devs = $esxcli.storage.core.device.list.Invoke() | Where-Object { $_.IsLocal -eq 'false' }
        foreach ($d in $devs) {
            try {
                $stat = $esxcli.storage.core.device.vaai.status.get.Invoke(@{ device = $d.Device })
                $issues = @()
                if ($stat.ATSStatus -ne 'supported') { $issues += "ATS=$($stat.ATSStatus)" }
                if ($stat.XCOPYStatus -ne 'supported') { $issues += "XCOPY=$($stat.XCOPYStatus)" }
                if ($stat.WriteSameStatus -ne 'supported') { $issues += "WriteSame=$($stat.WriteSameStatus)" }
                if ($issues.Count -gt 0) {
                    [pscustomobject]@{
                        Host           = $h.Name
                        Device         = $d.Device
                        Vendor         = $d.Vendor
                        Model          = $d.Model
                        ATS            = $stat.ATSStatus
                        XCOPY          = $stat.XCOPYStatus
                        WriteSame      = $stat.WriteSameStatus
                        Issue          = ($issues -join '; ')
                    }
                }
            } catch { continue }
        }
    } catch { }
    break  # one host is enough; LUNs are presented identically across the cluster
}
