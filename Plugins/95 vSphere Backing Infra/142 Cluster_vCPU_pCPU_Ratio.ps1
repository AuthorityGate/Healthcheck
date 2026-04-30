# Start of Settings
$WarnRatio = 5
$BadRatio  = 8
# End of Settings

$Title          = 'Cluster vCPU : pCPU Oversubscription'
$Header         = 'Per-cluster aggregate vCPU vs pCPU ratio (every cluster listed)'
$Comments       = 'Aggregate vCPU (sum of NumCpu across powered-on VMs) divided by pCPU (sum of physical cores). VDI tolerates 5:1 - 8:1; server workloads typically 1.5:1 - 3:1. High ratios cause CPU ready (KB 2002181) under load. Lists every cluster regardless of ratio so operators can see current density.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.1
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Right-size oversubscribed VMs, scale out the cluster, or split workloads by tier. Pair clusters at >= $WarnRatio : 1 with the VM CPU Ready Outliers plugin to confirm whether oversubscription is hurting in practice."

if (-not $Global:VCConnected) { return }

$clusters = @(Get-Cluster -ErrorAction SilentlyContinue | Sort-Object Name)
if ($clusters.Count -eq 0) {
    [pscustomobject]@{ Note = 'No clusters returned by Get-Cluster.' }
    return
}

foreach ($c in $clusters) {
    $hosts = @($c | Get-VMHost -ErrorAction SilentlyContinue)
    if ($hosts.Count -eq 0) {
        [pscustomobject]@{ Cluster=$c.Name; Hosts=0; pCPU=''; vCPUOn=''; Ratio=''; Status='NO HOSTS' }
        continue
    }
    $pcpu  = ($hosts | Measure-Object -Property NumCpu -Sum).Sum
    $vmsOn = @($c | Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.PowerState -eq 'PoweredOn' })
    $vmsOff = @($c | Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.PowerState -eq 'PoweredOff' })
    $vcpuOn  = ($vmsOn  | Measure-Object -Property NumCpu -Sum).Sum
    $vcpuOff = ($vmsOff | Measure-Object -Property NumCpu -Sum).Sum

    $ratio = if ($pcpu -gt 0 -and $vcpuOn) { [math]::Round([double]$vcpuOn / [double]$pcpu, 2) } else { 0 }
    $status = if ($ratio -ge $BadRatio) { "BAD (>= $BadRatio:1)" }
              elseif ($ratio -ge $WarnRatio) { "WARN (>= $WarnRatio:1)" }
              elseif ($pcpu -le 0) { 'NO pCPU' }
              else { 'OK' }

    [pscustomobject]@{
        Cluster        = $c.Name
        Hosts          = $hosts.Count
        pCPUCores      = $pcpu
        vCPUPoweredOn  = [int]$vcpuOn
        vCPUPoweredOff = [int]$vcpuOff
        Ratio          = "$ratio : 1"
        WarnAt         = "$WarnRatio : 1"
        BadAt          = "$BadRatio : 1"
        Status         = $status
        VMsOn          = $vmsOn.Count
        VMsOff         = $vmsOff.Count
    }
}

$TableFormat = @{
    Ratio = { param($v,$row)
        $r = 0; try { $r = [decimal](("$v" -split ' : ')[0]) } catch { }
        if ($r -ge 8) { 'bad' } elseif ($r -ge 5) { 'warn' } else { '' }
    }
    Status = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -match 'BAD') { 'bad' } elseif ("$v" -match 'WARN|NO') { 'warn' } else { '' } }
}
