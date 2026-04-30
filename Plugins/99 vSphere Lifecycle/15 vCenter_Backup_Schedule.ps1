# Start of Settings
# End of Settings

$Title          = 'vCenter File-Based Backup Schedule'
$Header         = "vCenter VAMI backup schedule + last-run state"
$Comments       = "VCSA appliance has a built-in file-based backup feature (VAMI -> Backup). Backs up vmware-vpostgres + config to SFTP/HTTPS/etc. Without this, vCenter recovery from disaster = full appliance redeploy."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P1'
$Recommendation = "If no schedule configured: enable VAMI backup with daily cadence to SFTP target. Test restore quarterly. Backup encryption passphrase in vault."

if (-not $Global:VCConnected) { return }

# VAMI backup is queryable via REST: /api/appliance/recovery/backup/schedules
# This plugin notes its presence as guidance - actual API call requires VAMI session.
# We surface a guidance row for the consultant to verify.

$vc = $Global:DefaultVIServer
if (-not $vc) {
    [pscustomobject]@{
        VCenter = 'unknown'
        BackupConfigured = '(unable to query)'
        Note = 'vCenter session not available.'
    }
    return
}

[pscustomobject]@{
    VCenter           = $vc.Name
    BackupConfigured  = '(check VAMI manually)'
    SchedulePath      = "https://$($vc.Name):5480/#?backup-schedule"
    Note              = "PowerCLI cannot query VAMI backup directly. Verify in VAMI: Login -> Backup -> Backup Schedules. Confirm Active=true, daily cadence, SFTP target reachable. Last successful run < 24h."
    Recommendation    = 'Enable backup, set daily cadence, store passphrase in vault, test restore quarterly.'
}
