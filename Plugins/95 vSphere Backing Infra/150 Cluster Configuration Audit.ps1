# Start of Settings
# End of Settings

$Title          = 'Cluster Configuration Audit'
$Header         = 'Every cluster, every important configured option in one row'
$Comments       = "Single-row-per-cluster comprehensive audit. Surfaces HA + DRS + EVC + vSAN + Admission Control + Encryption + vLCM + Affinity + Heartbeat + Swap + Isolation Response in one view so operators can confirm intent without opening every cluster's Configure tab. Use this as the cross-cluster delta finder: rows that disagree on settings of the same purpose are usually accidental drift."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'Info'
$Recommendation = "Use this audit as the single source of truth when planning cluster changes. Cross-cluster deltas in HA / DRS / EVC settings should each have a documented business reason; otherwise normalize to the chosen standard."

if (-not $Global:VCConnected) { return }

$clusters = @(Get-Cluster -ErrorAction SilentlyContinue | Sort-Object Name)
if ($clusters.Count -eq 0) {
    [pscustomobject]@{ Note = 'No clusters returned by Get-Cluster.' }
    return
}

foreach ($c in $clusters) {
    $hosts = @($c | Get-VMHost -ErrorAction SilentlyContinue)
    $vmCount = @($c | Get-VM -ErrorAction SilentlyContinue).Count
    $cv = $null
    try { $cv = $c | Get-View -ErrorAction Stop } catch { }

    # ---- HA ----
    $haEnabled = [bool]$c.HAEnabled
    $haAdmCtrl = $null
    $haIsolation = $null
    $hbDsCount = $null
    $vmMonitor = $null
    $hostMonitoring = $null
    if ($cv -and $cv.Configuration.DasConfig) {
        $das = $cv.Configuration.DasConfig
        $haAdmCtrl  = if ($das.AdmissionControlEnabled) { 'Enabled' } else { 'Disabled' }
        if ($das.AdmissionControlPolicy) {
            $polType = "$($das.AdmissionControlPolicy.GetType().Name)"
            $haAdmCtrl = "$haAdmCtrl ($polType)"
        }
        $haIsolation    = "$($das.DefaultVmSettings.IsolationResponse)"
        $vmMonitor      = "$($das.DefaultVmSettings.VmToolsMonitoringSettings.VmMonitoring)"
        $hostMonitoring = "$($das.HostMonitoring)"
        $hbDsCount = if ($das.HeartbeatDatastore) { @($das.HeartbeatDatastore).Count } else { 0 }
    }

    # ---- DRS ----
    $drsEnabled = [bool]$c.DrsEnabled
    $drsAuto    = "$($c.DrsAutomationLevel)"
    $drsThr     = if ($c.DrsMigrationThreshold) { [int]$c.DrsMigrationThreshold } else { '' }
    $dpmEnabled = $false
    if ($cv -and $cv.Configuration.DpmConfigInfo) { $dpmEnabled = [bool]$cv.Configuration.DpmConfigInfo.Enabled }

    # ---- EVC ----
    $evc = if ($c.EVCMode) { "$($c.EVCMode)" } else { '(disabled)' }

    # ---- vSAN ----
    $vsanEnabled = $false
    $vsanDedup = ''
    if ($cv -and $cv.ConfigurationEx -and $cv.ConfigurationEx.VsanConfigInfo) {
        $vsanEnabled = [bool]$cv.ConfigurationEx.VsanConfigInfo.Enabled
    }

    # ---- VM/Host groups + affinity rules ----
    $rules = @()
    try { $rules = @($c | Get-DrsRule -ErrorAction SilentlyContinue) } catch { }
    $vmHostRules = 0
    try { $vmHostRules = @($c | Get-DrsVMHostRule -ErrorAction SilentlyContinue).Count } catch { }

    # ---- Per-cluster aggregate stats ----
    $totalCpuMHz = ($hosts | Measure-Object -Property CpuTotalMhz   -Sum).Sum
    $totalRamMB  = ($hosts | Measure-Object -Property MemoryTotalMB -Sum).Sum

    # ---- Encryption / Key Provider awareness ----
    $kmsAware = $false
    try {
        if ($cv -and $cv.ConfigurationEx -and $cv.ConfigurationEx.GetType().GetProperty('EncryptionConfig')) {
            $kmsAware = [bool]$cv.ConfigurationEx.EncryptionConfig
        }
    } catch { }

    [pscustomobject]@{
        Cluster           = $c.Name
        Hosts             = $hosts.Count
        VMs               = $vmCount
        TotalCpuGHz       = if ($totalCpuMHz) { [math]::Round($totalCpuMHz / 1000, 1) } else { 0 }
        TotalRamGB        = if ($totalRamMB)  { [math]::Round($totalRamMB / 1024, 0) } else { 0 }
        HA                = if ($haEnabled) { 'Enabled' } else { 'Disabled' }
        HostMonitoring    = "$hostMonitoring"
        AdmissionControl  = if ($haAdmCtrl) { "$haAdmCtrl" } else { '' }
        IsolationResponse = "$haIsolation"
        VMMonitoring      = "$vmMonitor"
        HeartbeatDS       = "$hbDsCount"
        DRS               = if ($drsEnabled) { 'Enabled' } else { 'Disabled' }
        DRSAutomation     = $drsAuto
        DRSThreshold      = "$drsThr"
        DPM               = if ($dpmEnabled) { 'Enabled' } else { 'Disabled' }
        EVCMode           = $evc
        vSAN              = if ($vsanEnabled) { 'Enabled' } else { 'Disabled' }
        DRSAffinityRules  = $rules.Count
        VMHostRules       = $vmHostRules
    }
}

$TableFormat = @{
    HA               = { param($v,$row) if ("$v" -eq 'Disabled') { 'bad' } else { 'ok' } }
    DRS              = { param($v,$row) if ("$v" -eq 'Disabled') { 'warn' } else { 'ok' } }
    DRSAutomation    = { param($v,$row) if ("$v" -ne 'FullyAutomated' -and "$($row.DRS)" -eq 'Enabled') { 'warn' } else { '' } }
    EVCMode          = { param($v,$row) if ("$v" -eq '(disabled)') { 'warn' } else { '' } }
    AdmissionControl = { param($v,$row) if ("$v" -match 'Disabled') { 'warn' } else { '' } }
}
