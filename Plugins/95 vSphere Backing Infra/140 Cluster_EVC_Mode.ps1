# Start of Settings
# End of Settings

$Title          = 'Cluster EVC Mode'
$Header         = 'Per-cluster EVC baseline (every cluster listed)'
$Comments       = 'Enhanced vMotion Compatibility (EVC) baselines CPU feature exposure across hosts in a cluster. Without EVC, mixing CPU generations breaks vMotion. Even on a homogenous cluster, setting EVC future-proofs hardware refresh. Lists every cluster with the actual baseline name (e.g. intel-icelake, amd-rome) so operators can verify what is configured, not just whether something is configured.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.1
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = 'Cluster -> Configure -> VMware EVC -> Enable. Choose the lowest-generation CPU baseline that all current and likely future hosts can match. Modern recommendation: intel-cascadelake or intel-icelake for Intel; amd-rome or amd-milan for AMD. Per-VM EVC is also available for migrating across vCenters.'

if (-not $Global:VCConnected) { return }

$clusters = @(Get-Cluster -ErrorAction SilentlyContinue | Sort-Object Name)
if ($clusters.Count -eq 0) {
    [pscustomobject]@{ Note = 'No clusters returned by Get-Cluster.' }
    return
}

foreach ($c in $clusters) {
    $hosts = @($c | Get-VMHost -ErrorAction SilentlyContinue)
    $cpuModels = @($hosts | ForEach-Object { try { (Get-View $_.Id -Property 'Hardware.CpuPkg' -ErrorAction SilentlyContinue).Hardware.CpuPkg | Select-Object -First 1 -ExpandProperty Description } catch { } } | Where-Object { $_ } | Select-Object -Unique)
    $vendors = @($cpuModels | ForEach-Object { if ("$_" -match 'Intel') { 'Intel' } elseif ("$_" -match 'AMD') { 'AMD' } else { 'Unknown' } } | Select-Object -Unique)

    $evc = "$($c.EVCMode)"
    $perVmEvc = $false
    try {
        $cv = $c | Get-View -ErrorAction Stop
        if ($cv -and $cv.Configuration.PerHostSwapFile) { } # placeholder
        # Per-VM EVC is at VM level; cluster only carries cluster-wide baseline.
    } catch { }

    $status = if (-not $evc) { 'DISABLED' }
              elseif ($vendors.Count -gt 1) { "MIXED VENDOR ($($vendors -join '+')) - EVC baseline cannot bridge Intel<->AMD" }
              else { "OK ($evc)" }

    [pscustomobject]@{
        Cluster      = $c.Name
        EVCMode      = if ($evc) { $evc } else { '(disabled)' }
        Hosts        = $hosts.Count
        CpuVendors   = ($vendors -join ', ')
        CpuModels    = if ($cpuModels.Count -le 3) { ($cpuModels -join '; ') } else { (($cpuModels | Select-Object -First 3) -join '; ') + " ... +$($cpuModels.Count - 3) more" }
        Status       = $status
    }
}

$TableFormat = @{
    EVCMode = { param($v,$row) if ("$v" -eq '(disabled)') { 'warn' } else { '' } }
    Status  = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'DISABLED') { 'warn' } elseif ("$v" -match 'MIXED VENDOR') { 'bad' } else { '' } }
}
