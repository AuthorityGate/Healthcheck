# Start of Settings
# End of Settings

$Title          = 'Persistent Disk Size Drift'
$Header         = 'Persistent-disk distribution across pools'
$Comments       = 'Mixed persistent-disk sizes within a pool (typically due to manual expansion) complicate refresh.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '50 Machines'
$Severity       = 'P3'
$Recommendation = 'Standardize persistent-disk size at pool creation. Re-image to push to standard size.'

if (-not (Get-HVRestSession)) { return }
$m = Get-HVMachine
if (-not $m) { return }
$m | Where-Object { $_.persistent_disk_size_in_mb -gt 0 } | Group-Object persistent_disk_size_in_mb |
    ForEach-Object { [pscustomobject]@{ PersistentDiskMB = $_.Name; Count = $_.Count } }

