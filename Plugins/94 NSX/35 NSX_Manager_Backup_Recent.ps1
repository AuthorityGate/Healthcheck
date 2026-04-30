# Start of Settings
# End of Settings

$Title          = 'NSX Manager Backup Recent State'
$Header         = "NSX backup last-run state"
$Comments       = "NSX state = irreplaceable network configuration. Backup tested + recent = the only path to recover from cluster loss."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P1'
$Recommendation = "Backup interval = hourly for change-heavy, daily minimum. Verify SFTP target reachable. Test restore quarterly. Passphrase in vault."

if (-not (Get-NSXRestSession)) { return }

try {
    $hist = Invoke-NSXRest -Path '/api/v1/cluster/backups/history' -Method GET
    if (-not $hist) {
        [pscustomobject]@{
            BackupType = '(no history)'
            LastRun = ''
            Status = ''
            Note = 'No backup history - configure backup schedule.'
        }
        return
    }
    foreach ($k in 'cluster_backup_statuses','node_backup_statuses') {
        if ($hist.$k) {
            foreach ($b in @($hist.$k | Select-Object -First 3)) {
                $ts = if ($b.end_time) { (Get-Date '1970-01-01').AddMilliseconds([int64]$b.end_time) } else { $null }
                $age = if ($ts) { [int]((Get-Date) - $ts).TotalHours } else { $null }
                [pscustomobject]@{
                    BackupType = $k -replace '_statuses',''
                    LastRun    = if ($ts) { $ts.ToString('yyyy-MM-dd HH:mm') } else { '' }
                    AgeHours   = $age
                    Success    = $b.success
                    Note       = if ($age -ne $null -and $age -gt 48) { 'Backup > 48h old' } elseif (-not $b.success) { 'Last backup FAILED' } else { '' }
                }
            }
        }
    }
} catch { }

$TableFormat = @{
    Note = { param($v,$row) if ($v -match 'FAILED|> 48h') { 'bad' } else { '' } }
    Success = { param($v,$row) if ($v -eq $false) { 'bad' } else { '' } }
}
