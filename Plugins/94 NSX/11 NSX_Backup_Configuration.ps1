# Start of Settings
# End of Settings

$Title          = 'NSX Backup Configuration'
$Header         = 'Scheduled backup target'
$Comments       = "Reference: 'Backup and Restore' (NSX docs). Backup is mandatory; restore depends on it."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P1'
$Recommendation = 'Configure SFTP backup target; schedule daily; verify last-success date.'

if (-not (Get-NSXRestSession)) { return }
try { $b = Get-NSXBackupConfig } catch { return }
if (-not $b) { return }
[pscustomobject]@{
    BackupEnabled    = $b.backup_enabled
    Schedule         = $b.backup_schedule.resource_type
    SftpServer       = $b.remote_file_server.server
    SftpDirectory    = $b.remote_file_server.directory_path
    InventoryEnabled = $b.inventory_summary_interval -gt 0
}
