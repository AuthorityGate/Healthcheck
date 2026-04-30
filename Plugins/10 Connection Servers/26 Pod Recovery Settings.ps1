# Start of Settings
# End of Settings

$Title          = 'Pod Recovery Configuration'
$Header         = 'Pod backup / recovery posture'
$Comments       = "Reference: 'Backing Up Horizon Configuration Data' (Horizon Admin Guide). LDAP backups are scheduled per-pod and are required for disaster recovery."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'P2'
$Recommendation = "Verify ADAM/LDAP backup schedule, target path, and retention. Test a 'vdmexport' restore to lab quarterly."

if (-not (Get-HVRestSession)) { return }
try { $b = Invoke-HVRest -Path '/v1/config/data-recovery-settings' -NoPaging } catch { return }
if (-not $b) { return }
[pscustomobject]@{
    BackupFrequency        = $b.backup_frequency
    MaxNumberOfBackups     = $b.max_number_of_backups
    BackupFolder           = $b.folder_location
    EncryptionEnabled      = $b.encrypted_backup_enabled
    LastBackupTime         = if ($b.last_backup_time) { (Get-Date '1970-01-01').AddMilliseconds($b.last_backup_time).ToLocalTime() } else { $null }
}

