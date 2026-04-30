# Start of Settings
$LookbackDays = 30
# End of Settings

$Title          = 'Recent Host Disconnect Events (30 days)'
$Header         = '[count] host-disconnect/reconnect event(s) in last ' + $LookbackDays + ' day(s)'
$Comments       = 'vCenter <-> ESXi heartbeat losses past 30 days. Frequent disconnects = mgmt-network instability, hostd crashes, or storage stalls (hostd blocked on storage I/O). Each disconnect can trigger HA isolation response and downstream chaos.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P2'
$Recommendation = 'Pull /var/log/hostd.log around each event time. Look for storage I/O timeouts (PDL/APD), heartbeat datastore issues, NIC link flap. Audit physical mgmt switch + cable.'

if (-not $Global:VCConnected) { return }

$start = (Get-Date).AddDays(-$LookbackDays)
try {
    $events = Get-VIEvent -Start $start -Finish (Get-Date) -MaxSamples 5000 -ErrorAction Stop |
        Where-Object { $_.GetType().Name -match 'HostConnectionLostEvent|HostConnectedEvent|HostNotRespondingEvent|HostReconnectionFailedEvent' }

    foreach ($e in $events) {
        [pscustomobject]@{
            Time      = $e.CreatedTime
            Host      = if ($e.Host) { $e.Host.Name } else { '' }
            EventType = $e.GetType().Name
            Message   = ($e.FullFormattedMessage -split "`n" | Select-Object -First 1)
        }
    }
} catch { }
