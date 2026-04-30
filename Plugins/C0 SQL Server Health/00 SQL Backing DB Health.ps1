# Start of Settings
# Operator hint: $Global:SQLConnectionStrings = @(
#   @{ Name='Horizon Event DB'; ConnectionString='Server=sql1.corp.local;Database=ViewEventDB;Integrated Security=true' }
#   @{ Name='App Volumes DB'; ConnectionString='Server=sql1.corp.local;Database=AppVolumes;Integrated Security=true' }
#   @{ Name='vCenter DB'; ConnectionString='Server=sql1.corp.local;Database=vcDB;Integrated Security=true' }
# )
# End of Settings

$Title          = "SQL Server Backing DB Health"
$Header         = "[count] SQL database(s) probed"
$Comments       = "Reads basic health metrics for the SQL Server databases that back Horizon, App Volumes, and (legacy) vCenter: db state, size, log size, free space, last full backup, recovery model. Out-of-space tempdb / silent log-full / no-recent-backup all silently break operations. Uses Integrated Security by default; supports SQL auth via the connection string."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "C0 SQL Server Health"
$Severity       = "P1"
$Recommendation = "DBs with no full backup in 7+ days = recovery-objective gap. Recovery model SIMPLE on a transaction-heavy DB = no point-in-time recovery. Free space < 10% of allocated = imminent autogrow stall."

if (-not $Global:SQLConnectionStrings) {
    [pscustomobject]@{ Note='No SQL connection strings configured. Set $Global:SQLConnectionStrings (array of @{Name=;ConnectionString=}) in runner OR Specialized Scope.' }
    return
}

foreach ($entry in $Global:SQLConnectionStrings) {
    $name = if ($entry.Name) { $entry.Name } else { 'unnamed' }
    $row = [ordered]@{
        Database          = $name
        Server            = ''
        DatabaseName      = ''
        State             = ''
        DataSizeMB        = ''
        LogSizeMB         = ''
        FreeSpaceMB       = ''
        LastFullBackup    = ''
        DaysSinceBackup   = ''
        RecoveryModel     = ''
        Note              = ''
    }
    try {
        $cn = New-Object System.Data.SqlClient.SqlConnection $entry.ConnectionString
        $cn.Open()
        $row.Server = $cn.DataSource
        $row.DatabaseName = $cn.Database
        $cmd = $cn.CreateCommand()
        $cmd.CommandText = @"
SELECT
  d.state_desc AS state,
  CAST(SUM(CASE WHEN type=0 THEN size ELSE 0 END)/128.0 AS int) AS data_mb,
  CAST(SUM(CASE WHEN type=1 THEN size ELSE 0 END)/128.0 AS int) AS log_mb,
  d.recovery_model_desc AS recovery_model
FROM sys.master_files mf
JOIN sys.databases d ON d.database_id = mf.database_id
WHERE d.name = DB_NAME()
GROUP BY d.state_desc, d.recovery_model_desc
"@
        $rdr = $cmd.ExecuteReader()
        if ($rdr.Read()) {
            $row.State = [string]$rdr['state']
            $row.DataSizeMB = [int]$rdr['data_mb']
            $row.LogSizeMB  = [int]$rdr['log_mb']
            $row.RecoveryModel = [string]$rdr['recovery_model']
        }
        $rdr.Close()
        # Free space
        $cmd.CommandText = "SELECT SUM(CAST(unallocated_extent_page_count AS bigint))*8/1024 FROM sys.dm_db_file_space_usage"
        try {
            $free = $cmd.ExecuteScalar()
            $row.FreeSpaceMB = [int]$free
        } catch { }
        # Last full backup
        $cmd.CommandText = "SELECT MAX(backup_finish_date) FROM msdb.dbo.backupset WHERE database_name = DB_NAME() AND type='D'"
        try {
            $lastBackup = $cmd.ExecuteScalar()
            if ($lastBackup -and $lastBackup -ne [DBNull]::Value) {
                $row.LastFullBackup = ([datetime]$lastBackup).ToString('yyyy-MM-dd HH:mm')
                $row.DaysSinceBackup = [int]((Get-Date) - [datetime]$lastBackup).TotalDays
            }
        } catch { }
        $cn.Close()
    } catch {
        $row.Note = $_.Exception.Message
    }
    [pscustomobject]$row
}

$TableFormat = @{
    State             = { param($v,$row) if ($v -eq 'ONLINE') { 'ok' } elseif ($v) { 'bad' } else { '' } }
    DaysSinceBackup   = { param($v,$row) if ([int]"$v" -gt 7) { 'bad' } elseif ([int]"$v" -gt 1) { 'warn' } else { '' } }
    RecoveryModel     = { param($v,$row) if ($v -eq 'SIMPLE') { 'warn' } elseif ($v -eq 'FULL') { 'ok' } else { '' } }
}
