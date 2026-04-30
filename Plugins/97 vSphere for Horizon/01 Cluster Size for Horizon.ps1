# Start of Settings
# Horizon supports up to 64-host clusters with vSphere 7+ for instant-clone pools
# (Horizon Sizing Limits and Recommendations / KB 2150305 / 70327). Many shops
# still cap at 32 for blast radius. Tune to your standards.
$MaxHostsPerCluster = 64
$WarnHostsPerCluster = 32
# End of Settings

$Title          = "Horizon Cluster Sizing"
$Header         = "Per-cluster host count vs Horizon supported limits"
$Comments       = "Reference: 'Horizon Sizing Limits and Recommendations' (https://kb.vmware.com/s/article/70327) and 'Configuration Maximums' for the deployed Horizon version. > $MaxHostsPerCluster hosts is unsupported for instant clone; > $WarnHostsPerCluster is a blast-radius warning."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P2"
$Recommendation = "Split clusters that exceed the supported maximum into multiple clusters of equal size; assign each pool to one. Keep N+1 host capacity for HA on each."

if (-not $Global:VCConnected) { return }

Get-Cluster -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_.ExtensionData.Host.Count
    [pscustomobject]@{
        Cluster   = $_.Name
        HostCount = $h
        Verdict   = if     ($h -gt $MaxHostsPerCluster)  { "Over supported max ($MaxHostsPerCluster)" }
                    elseif ($h -gt $WarnHostsPerCluster) { "Above local cap ($WarnHostsPerCluster)" }
                    else                                  { "OK" }
        HA        = $_.HAEnabled
        DRS       = $_.DrsEnabled
    }
}

$TableFormat = @{
    Verdict = { param($v,$row) if ($v -like 'Over*') { 'bad' } elseif ($v -like 'Above*') { 'warn' } else { 'ok' } }
}
