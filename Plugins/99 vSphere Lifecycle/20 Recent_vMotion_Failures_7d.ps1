# Start of Settings
$LookbackDays = 7
# End of Settings

$Title          = 'Recent vMotion Failures (7 days)'
$Header         = '[count] vMotion failure event(s) in last ' + $LookbackDays + ' day(s)'
$Comments       = 'vMotion failures past 7 days, grouped by source host / target host / VM. Recurring src/dest pairs point at network-side issues (dropped fragments, MTU drift, bond hash collisions). Recurring per-VM = VM-level issue (CPU compatibility, attached USB, lock conflict).'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P2'
$Recommendation = "For each repeat src/dest pair: vmkping jumbo across the vMotion VMK. For per-VM repeats: check VM device list (USB? unsupported HW?) and snapshot consolidation. Cross-reference with 80 VMK MTU drift and 04 Physical NIC link state."

if (-not $Global:VCConnected) { return }

$start = (Get-Date).AddDays(-$LookbackDays)
try {
    $events = Get-VIEvent -Start $start -Finish (Get-Date) -MaxSamples 5000 -ErrorAction Stop |
        Where-Object {
            $_.GetType().Name -match 'MigrationError|MigrationWarning|MigrationFailedEvent|MigrationResourceWarningEvent' -or
            $_.FullFormattedMessage -match 'migration.*fail|vmotion.*fail'
        }

    foreach ($e in $events) {
        [pscustomobject]@{
            Time         = $e.CreatedTime
            VM           = if ($e.Vm) { $e.Vm.Name } else { '' }
            SrcHost      = if ($e.Host) { $e.Host.Name } else { '' }
            DestHost     = if ($e.DestHost) { $e.DestHost.Name } else { '' }
            EventType    = $e.GetType().Name
            Message      = ($e.FullFormattedMessage -split "`n" | Select-Object -First 1)
        }
    }
} catch { }
