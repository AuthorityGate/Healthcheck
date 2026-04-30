# Start of Settings
# End of Settings

$Title          = "Pool Provisioning Errors"
$Header         = "[count] pool(s) have provisioning halted or errored"
$Comments       = "Pools with provisioning errors block new desktops from spinning up - common causes: parent VM power state, snapshot deleted, vCenter creds expired, datastore full."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "30 Desktop Pools"
$Severity       = "P1"
$Recommendation = "Open Horizon Console -> Inventory -> Desktops -> select pool -> Tasks/Events. Resolve the underlying vCenter/storage error and click 'Resume Provisioning'."

$pools = Get-HVDesktopPool
if (-not $pools) { return }

$bad = foreach ($p in $pools) {
    $st = $null
    if ($p.provisioning_status_data) { $st = $p.provisioning_status_data.provisioning_state }
    if ($st -in 'PROVISIONING_ERROR','PROVISIONING_DISABLED_BY_ADMIN','PROVISIONING_HALTED') {
        [pscustomobject]@{
            Name           = $p.name
            Type           = $p.type
            Source         = $p.source
            ProvState      = $st
            ErrorVMs       = if ($p.provisioning_status_data) { $p.provisioning_status_data.num_machines_in_error } else { 0 }
            ConfiguredSize = if ($p.provisioning_settings) { $p.provisioning_settings.max_number_of_machines } else { 0 }
            CurrentSize    = if ($p.machine_count) { $p.machine_count } else { 0 }
        }
    }
}
$bad

$TableFormat = @{
    ProvState = { param($v,$row) 'bad' }
    ErrorVMs  = { param($v,$row) if ([int]$v -gt 0) { 'bad' } else { '' } }
}
