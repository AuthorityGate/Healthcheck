# Start of Settings
# End of Settings

$Title          = 'HA Admission Control Configuration'
$Header         = "[count] cluster(s) with HA admission-control settings"
$Comments       = "HA admission control reserves capacity for failover. Wrong policy = either over-reserve (waste) or under-reserve (failover fails to restart VMs)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Cluster Resource Percentage = 1/N (where N=hosts) is standard. Verify HA enabled + admission control active."

if (-not $Global:VCConnected) { return }

foreach ($cl in (Get-Cluster -ErrorAction SilentlyContinue)) {
    $ha = $cl.HAEnabled
    $admControl = $cl.HAAdmissionControlEnabled
    $hosts = (Get-VMHost -Location $cl).Count
    [pscustomobject]@{
        Cluster                  = $cl.Name
        HAEnabled                = $ha
        AdmissionControlEnabled  = $admControl
        FailoverLevel            = $cl.HAFailoverLevel
        HostCount                = $hosts
        IsolationResponse        = $cl.HAIsolationResponse
        RestartPriority          = $cl.HARestartPriority
        Note                     = if (-not $ha) { 'HA DISABLED' } elseif (-not $admControl) { 'Admission Control DISABLED - failover may not have capacity' } else { '' }
    }
}

$TableFormat = @{
    HAEnabled = { param($v,$row) if (-not $v) { 'bad' } else { '' } }
    AdmissionControlEnabled = { param($v,$row) if (-not $v) { 'warn' } else { '' } }
}
