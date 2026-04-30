# Start of Settings
# End of Settings

$Title          = 'Host BIOS Date / Firmware Drift'
$Header         = '[count] host(s) in clusters with BIOS drift'
$Comments       = 'Different BIOS versions on hosts in the same cluster = inconsistent microcode (Spectre/Meltdown mitigations, EVC compatibility). Standardize BIOS version + date across the cluster.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = 'A0 Hardware'
$Severity       = 'P2'
$Recommendation = 'Standardize BIOS via vendor tooling (Dell DSU / HPE SUM / Lenovo XClarity / Cisco UCSM). Run a cluster-wide BIOS update during a maintenance window.'

if (-not $Global:VCConnected) { return }

foreach ($cl in (Get-Cluster -ErrorAction SilentlyContinue)) {
    $hosts = @(Get-VMHost -Location $cl -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionState -eq 'Connected' })
    if ($hosts.Count -lt 2) { continue }

    # Build per-host BIOS info first so we can decide if drift exists.
    $rows = foreach ($h in $hosts) {
        $b = $null
        try { $b = $h.ExtensionData.Hardware.BiosInfo } catch { }
        [pscustomobject]@{
            Host        = $h.Name
            Cluster     = $cl.Name
            BiosVersion = if ($b) { $b.BiosVersion } else { 'unknown' }
            ReleaseDate = if ($b -and $b.ReleaseDate) { ([datetime]$b.ReleaseDate).ToString('yyyy-MM-dd') } else { 'unknown' }
            Model       = $h.Model
        }
    }

    $distinctVersions = @($rows | Select-Object -ExpandProperty BiosVersion -Unique)
    $distinctDates    = @($rows | Select-Object -ExpandProperty ReleaseDate -Unique)
    if ($distinctVersions.Count -gt 1 -or $distinctDates.Count -gt 1) {
        # Emit one row per host so the report names every host that's part of the
        # drift, not just one row per cluster.
        foreach ($r in $rows) { $r }
    }
}
