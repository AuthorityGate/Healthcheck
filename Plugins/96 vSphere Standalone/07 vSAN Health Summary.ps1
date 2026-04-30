# Start of Settings
# End of Settings

$Title          = "vSAN Cluster Health"
$Header         = "[count] vSAN cluster(s) reporting health issues"
$Comments       = "VMware vSAN Health Service surfaces hardware compat (HCL) drift, disk-group state, network partition, performance service, encryption, dedupe-compression, and cluster operations. Reference: KB 2114803."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P1"
$Recommendation = "Drill into Cluster -> Monitor -> vSAN -> Skyline Health to triage each red/yellow check. HCL warnings: download latest HCL via 'Update from File' (offline) or auto-refresh."

if (-not $Global:VCConnected) { return }

Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.VsanEnabled } | ForEach-Object {
    $cl = $_
    try {
        $hs = Get-VsanClusterHealth -Cluster $cl -ErrorAction SilentlyContinue
    } catch { return }
    if (-not $hs) { return }
    foreach ($g in $hs.Groups) {
        foreach ($t in $g.Tests) {
            if ($t.TestStatus -ne 'green' -and $t.TestStatus -ne 'skipped' -and $t.TestStatus -ne 'info') {
                [pscustomobject]@{
                    Cluster   = $cl.Name
                    Group     = $g.GroupName
                    Test      = $t.TestName
                    Status    = $t.TestStatus
                }
            }
        }
    }
}

$TableFormat = @{ Status = { param($v,$row) if ($v -eq 'red') { 'bad' } elseif ($v -eq 'yellow') { 'warn' } else { '' } } }
