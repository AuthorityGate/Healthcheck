# Start of Settings
# End of Settings

$Title          = 'DRS Power Management (DPM)'
$Header         = 'Per-cluster DPM state (Off recommended unless WOL/IPMI is validated)'
$Comments       = "Distributed Power Management (DPM) hibernates idle ESXi hosts to save power. Most production VDI/EUC clusters keep DPM Off (capacity-on-demand workloads). DPM Manual is rare. DPM Automatic should only be enabled on clusters with proven boot reliability and validated BMC/IPMI/WOL integration. Lists every DRS-enabled cluster's DPM state."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.1
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P3'
$Recommendation = "Cluster -> Configure -> vSphere DRS -> Edit -> Power Management. Default = Off. Enable Automatic only after validating IPMI/iLO/iDRAC wake-on-LAN reliability across the fleet."

if (-not $Global:VCConnected) { return }

$clusters = @(Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.DrsEnabled } | Sort-Object Name)
if ($clusters.Count -eq 0) {
    [pscustomobject]@{ Note = 'No DRS-enabled clusters returned. DPM requires DRS, so this check has nothing to evaluate.' }
    return
}

foreach ($c in $clusters) {
    $enabled = $false
    $level = 'Off'
    try {
        $cv = ($c | Get-View -ErrorAction Stop)
        $dpm = $cv.Configuration.DpmConfigInfo
        if ($dpm) {
            $enabled = [bool]$dpm.Enabled
            if ($enabled) { $level = "$($dpm.DefaultDpmBehavior)" } else { $level = 'Off' }
        }
    } catch {
        $level = "(query failed: $($_.Exception.Message))"
    }

    [pscustomobject]@{
        Cluster         = $c.Name
        DPMEnabled      = $enabled
        AutomationLevel = $level
        HostCount       = @($c | Get-VMHost -ErrorAction SilentlyContinue).Count
        Status          = if (-not $enabled) { 'OK (DPM off)' }
                          elseif ($level -eq 'manual') { 'REVIEW (manual)' }
                          else { 'REVIEW (automatic)' }
        Note            = if ($enabled) { 'DPM enabled - validate WOL across all hosts; DPM evacuations during night windows can mask hardware faults.' } else { '' }
    }
}

$TableFormat = @{
    DPMEnabled = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
    Status     = { param($v,$row) if ("$v" -match 'OK') { 'ok' } elseif ("$v" -match 'REVIEW') { 'warn' } else { '' } }
}
