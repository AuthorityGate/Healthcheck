# Start of Settings
# End of Settings

$Title          = "Cluster HA / DRS Configuration"
$Header         = "[count] cluster(s) profiled for HA + DRS settings"
$Comments       = "Per-cluster HA admission control, DRS automation level, EVC mode, and proactive HA. Off-by-default features (proactive HA, vSAN-Stretched, vMotion-Encrypted) are easy to miss without an explicit audit."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "Info"
$Recommendation = "DRS Automation = Fully Automated for VDI clusters (manual = users will see one-host-overload symptoms). HA host failure tolerance must reserve enough capacity for largest expected outage (typically N+1 host)."

if (-not $Global:VCConnected) { return }

$clusters = @(Get-Cluster -ErrorAction SilentlyContinue)
foreach ($c in $clusters) {
    if (-not $c) { continue }
    $view = $null
    try { $view = Get-View $c.Id -Property 'Configuration','Summary' -ErrorAction Stop } catch { }
    [pscustomobject]@{
        Cluster   = $c.Name
        HostCount = $c.ExtensionData.Host.Count
        DRSEnabled = $c.DrsEnabled
        DRSAutomationLevel = $c.DrsAutomationLevel
        DRSMigrationThreshold = if ($view) { $view.Configuration.DrsConfig.VmotionRate } else { '' }
        HAEnabled = $c.HAEnabled
        HAFailoverLevel = $c.HAFailoverLevel
        HAAdmissionControl = if ($view) { $view.Configuration.DasConfig.AdmissionControlEnabled } else { '' }
        EVCMode  = $c.EVCMode
        VsanEnabled = $c.VsanEnabled
        Hosts = ($c | Get-VMHost -ErrorAction SilentlyContinue).Count
        VMs   = ($c | Get-VM -ErrorAction SilentlyContinue).Count
    }
}

$TableFormat = @{
    DRSEnabled = { param($v,$row) if ($v -eq $true) { 'ok' } else { 'warn' } }
    HAEnabled  = { param($v,$row) if ($v -eq $true) { 'ok' } else { 'warn' } }
    DRSAutomationLevel = { param($v,$row) if ($v -eq 'FullyAutomated') { 'ok' } elseif ($v -eq 'Manual') { 'bad' } elseif ($v) { 'warn' } else { '' } }
}
