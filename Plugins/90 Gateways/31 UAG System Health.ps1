# Start of Settings
# End of Settings

$Title          = "UAG System Health (CPU, Memory, Disk, Sessions)"
$Header         = "UAG live system health"
$Comments       = "Live appliance health from /monitor/system + /monitor/stats. Establishes whether the UAG is sized correctly for current load (often the root cause of intermittent BLAST disconnects)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "90 Gateways"
$Severity       = "Info"
$Recommendation = "VMware sizing: 4 vCPU + 8 GB RAM = ~2000 sessions; 8+8 = ~4000. Sustained CPU > 80% or RAM > 85% = scale-out (additional UAG nodes behind the LB) or scale-up."

if (-not (Get-UAGRestSession)) { return }
$rows = @()
try { $sys = Get-UAGSystemHealth } catch { $sys = $null }
try { $stat = Get-UAGMonitorStats } catch { $stat = $null }
try { $ver = Get-UAGVersion } catch { $ver = $null }
try { $cpu = Get-UAGCpuStats } catch { $cpu = $null }
try { $mem = Get-UAGMemoryStats } catch { $mem = $null }
try { $disk = Get-UAGDiskStats } catch { $disk = $null }

$rows += [pscustomobject]@{ Metric='Version';      Value=if ($ver) { $ver.version } else { '' } }
$rows += [pscustomobject]@{ Metric='Build';        Value=if ($ver) { $ver.buildNumber } else { '' } }
$rows += [pscustomobject]@{ Metric='Uptime';       Value=if ($sys) { $sys.upTime } else { '' } }
$rows += [pscustomobject]@{ Metric='CpuUtilPct';   Value=if ($cpu) { $cpu.usedPercent } elseif ($stat) { $stat.cpuUsage } else { '' } }
$rows += [pscustomobject]@{ Metric='MemUtilPct';   Value=if ($mem) { $mem.usedPercent } elseif ($stat) { $stat.memoryUsage } else { '' } }
$rows += [pscustomobject]@{ Metric='DiskFreePct';  Value=if ($disk) { $disk.freePercent } else { '' } }
$rows += [pscustomobject]@{ Metric='ActiveSessions'; Value=if ($stat) { $stat.activeSessions } else { '' } }
$rows += [pscustomobject]@{ Metric='BlastSessions';  Value=if ($stat) { $stat.blastSessions } else { '' } }
$rows += [pscustomobject]@{ Metric='TunnelSessions'; Value=if ($stat) { $stat.tunnelSessions } else { '' } }
$rows += [pscustomobject]@{ Metric='PCoIPSessions';  Value=if ($stat) { $stat.pcoipSessions } else { '' } }
$rows
