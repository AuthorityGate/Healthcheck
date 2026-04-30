# Start of Settings
# End of Settings

$Title          = 'NSX Backup Recent Status'
$Header         = 'Last 5 backup outcomes'
$Comments       = 'Failed backups silently accumulate; verify last-success.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P1'
$Recommendation = 'Resolve transport errors. Test restore quarterly to lab cluster.'

if (-not (Get-NSXRestSession)) { return }
try { $h = Get-NSXBackupHistory } catch { return }
if (-not $h) { return }
$h | Select-Object -First 5 | ForEach-Object {
    [pscustomobject]@{
        Time      = $_.start_time
        EndTime   = $_.end_time
        Status    = $_.success
        ErrorCode = $_.error_code
        SizeMB    = if ($_.size) { [math]::Round($_.size / 1MB, 1) } else { 0 }
    }
}
