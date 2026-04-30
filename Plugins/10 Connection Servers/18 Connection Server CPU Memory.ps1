# Start of Settings
# End of Settings

$Title          = 'Connection Server CPU / Memory Sizing'
$Header         = 'Per-CS configured size + 30-day vCenter utilization'
$Comments       = @"
Sizing pulled from vCenter (the CS VMs live there - Horizon's /v1/monitor/connection-servers payload is JWT-only on 8.6 and doesn't include CPU/RAM utilization). For each Connection Server we:
1. Resolve the matching VM in any connected vCenter by short name.
2. Read configured vCPU + RAM from the VM config (the as-built sizing).
3. Pull 30-day average + peak CPU% and Memory active% from vCenter perf counters.
VMware sizing baseline: 4 vCPU + 12 GB RAM minimum per CS for Horizon 8 (Broadcom KB 70327). Sustained > 70% CPU or > 80% RAM = add a replica or right-size.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '10 Connection Servers'
$Severity       = 'P3'
$Recommendation = 'Right-size or add a replica when 30-day CPU > 70% or memory > 80%. Verify the CS VM is dedicated (no co-located AD/DNS/SQL roles), has the recommended 4 vCPU / 12 GB floor, and is on the same cluster as its peers for affinity-rule predictability.'

if (-not (Get-HVRestSession)) { return }
$cs = Get-HVConnectionServer
if (-not $cs) { return }

# Skip vCenter probing if PowerCLI isn't connected (the runner exposes
# $global:DefaultVIServers when at least one vCenter has been added).
$haveVCenter = $false
try {
    if ($global:DefaultVIServers -and @($global:DefaultVIServers).Count -gt 0) { $haveVCenter = $true }
} catch { }

function Get-VMShortName {
    param([string]$Name)
    if (-not $Name) { return '' }
    # Strip any trailing FQDN
    return ($Name -split '\.')[0]
}

function Get-VCenterPerf {
    param([Parameter(Mandatory)]$Vm)
    # 30-day averages + peaks. 5-minute rollup keeps the call fast and
    # avoids triggering the realtime counter on a busy CS.
    $start = (Get-Date).AddDays(-30)
    $stats = @{ AvgCpu = $null; PeakCpu = $null; AvgMem = $null; PeakMem = $null }
    try {
        $cpu = Get-Stat -Entity $Vm -Stat 'cpu.usage.average' -IntervalMins 30 -Start $start -ErrorAction SilentlyContinue
        if ($cpu) {
            $vals = @($cpu | Where-Object { $null -ne $_.Value } | ForEach-Object { [double]$_.Value })
            if ($vals.Count -gt 0) {
                $stats.AvgCpu  = [math]::Round((($vals | Measure-Object -Average).Average), 1)
                $stats.PeakCpu = [math]::Round((($vals | Measure-Object -Maximum).Maximum), 1)
            }
        }
        $mem = Get-Stat -Entity $Vm -Stat 'mem.usage.average' -IntervalMins 30 -Start $start -ErrorAction SilentlyContinue
        if ($mem) {
            $vals = @($mem | Where-Object { $null -ne $_.Value } | ForEach-Object { [double]$_.Value })
            if ($vals.Count -gt 0) {
                $stats.AvgMem  = [math]::Round((($vals | Measure-Object -Average).Average), 1)
                $stats.PeakMem = [math]::Round((($vals | Measure-Object -Maximum).Maximum), 1)
            }
        }
    } catch { }
    return $stats
}

foreach ($c in $cs) {
    $shortName = Get-VMShortName -Name $c.name
    $vmSize = [pscustomobject]@{
        VmFound        = $false
        VmName         = ''
        VmHost         = ''
        VmCluster      = ''
        ConfiguredCpu  = $null
        ConfiguredRam  = $null
        AvgCpuPct      = $null
        PeakCpuPct     = $null
        AvgMemPct      = $null
        PeakMemPct     = $null
        Note           = ''
    }
    if ($haveVCenter -and $shortName) {
        try {
            $vm = Get-VM -Name $shortName -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($vm) {
                $vmSize.VmFound       = $true
                $vmSize.VmName        = $vm.Name
                try { $vmSize.VmHost  = $vm.VMHost.Name } catch { }
                try { $vmSize.VmCluster = (Get-Cluster -VM $vm -ErrorAction SilentlyContinue | Select-Object -First 1).Name } catch { }
                $vmSize.ConfiguredCpu = [int]$vm.NumCpu
                $vmSize.ConfiguredRam = [math]::Round([double]$vm.MemoryGB, 1)
                $perf = Get-VCenterPerf -Vm $vm
                $vmSize.AvgCpuPct     = $perf.AvgCpu
                $vmSize.PeakCpuPct    = $perf.PeakCpu
                $vmSize.AvgMemPct     = $perf.AvgMem
                $vmSize.PeakMemPct    = $perf.PeakMem
                if ($null -eq $perf.AvgCpu) { $vmSize.Note = 'VM found, no perf samples (powered off or out of retention)' }
            } else {
                $vmSize.Note = "No VM matching '$shortName' in connected vCenters"
            }
        } catch {
            $vmSize.Note = "vCenter lookup failed: $($_.Exception.Message)"
        }
    } elseif (-not $haveVCenter) {
        $vmSize.Note = 'No vCenter connected - sizing not available (Horizon REST does not expose CPU/RAM on 8.6)'
    }

    [pscustomobject]@{
        Name           = $c.name
        Version        = $c.version
        OsType         = $c.os_type
        VmName         = $vmSize.VmName
        Cluster        = $vmSize.VmCluster
        Host           = $vmSize.VmHost
        ConfigVCpu     = $vmSize.ConfiguredCpu
        ConfigRamGb    = $vmSize.ConfiguredRam
        Avg30dCpuPct   = $vmSize.AvgCpuPct
        Peak30dCpuPct  = $vmSize.PeakCpuPct
        Avg30dMemPct   = $vmSize.AvgMemPct
        Peak30dMemPct  = $vmSize.PeakMemPct
        SslOk          = ($c.certificate.valid)
        Note           = $vmSize.Note
    }
}

$TableFormat = @{
    ConfigVCpu = { param($v,$row)
        if ($null -eq $v -or "$v" -eq '') { '' }
        elseif ([int]$v -lt 4) { 'bad' }
        else { 'ok' }
    }
    ConfigRamGb = { param($v,$row)
        if ($null -eq $v -or "$v" -eq '') { '' }
        elseif ([double]$v -lt 12) { 'bad' }
        else { 'ok' }
    }
    Avg30dCpuPct = { param($v,$row)
        if ($null -eq $v -or "$v" -eq '') { '' }
        elseif ([double]$v -gt 70) { 'bad' }
        elseif ([double]$v -gt 50) { 'warn' }
        else { 'ok' }
    }
    Peak30dCpuPct = { param($v,$row)
        if ($null -eq $v -or "$v" -eq '') { '' }
        elseif ([double]$v -gt 90) { 'bad' }
        elseif ([double]$v -gt 80) { 'warn' }
        else { '' }
    }
    Avg30dMemPct = { param($v,$row)
        if ($null -eq $v -or "$v" -eq '') { '' }
        elseif ([double]$v -gt 80) { 'bad' }
        elseif ([double]$v -gt 65) { 'warn' }
        else { 'ok' }
    }
    Peak30dMemPct = { param($v,$row)
        if ($null -eq $v -or "$v" -eq '') { '' }
        elseif ([double]$v -gt 95) { 'bad' }
        elseif ([double]$v -gt 85) { 'warn' }
        else { '' }
    }
    Note = { param($v,$row)
        if ($v -match 'No VM matching|failed') { 'bad' }
        elseif ($v -match 'No vCenter|out of retention') { 'warn' }
        else { '' }
    }
}
