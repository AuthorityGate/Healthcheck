# Start of Settings
$LookbackDays = 30
# End of Settings

$Title          = 'Recent HA Failovers (30 days)'
$Header         = '[count] HA-triggered VM restart event(s) in last ' + $LookbackDays + ' day(s)'
$Comments       = 'HA-triggered VM restarts past 30 days. Each row = one VM that was restarted on a surviving host after an HA event. Pair with host-disconnect events (22) to see the root cause.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P2'
$Recommendation = 'For each cluster of failovers, identify the failing host (22 Recent host disconnect). Pull /var/log/syslog and /var/log/vmkernel.log from that host around the event time. Check HBA, NIC, and PSU logs.'

if (-not $Global:VCConnected) { return }

$start = (Get-Date).AddDays(-$LookbackDays)
try {
    $events = Get-VIEvent -Start $start -Finish (Get-Date) -MaxSamples 5000 -ErrorAction Stop |
        Where-Object {
            $_.GetType().Name -match 'VmFailoverFailed|HostDisconnectedEvent|VmPoweredOnEvent' -and
            ($_.FullFormattedMessage -match 'HA|failover|isolation|restart')
        }

    foreach ($e in $events) {
        [pscustomobject]@{
            Time      = $e.CreatedTime
            VM        = if ($e.Vm) { $e.Vm.Name } else { '' }
            Host      = if ($e.Host) { $e.Host.Name } else { '' }
            Cluster   = if ($e.ComputeResource) { $e.ComputeResource.Name } else { '' }
            EventType = $e.GetType().Name
            Message   = ($e.FullFormattedMessage -split "`n" | Select-Object -First 1)
        }
    }
} catch { }
