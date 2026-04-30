# Start of Settings
# End of Settings

$Title          = "DHCP Audit Log + Database Health"
$Header         = "Per-server: audit log enabled, DB backup path, last cleanup, fragmentation"
$Comments       = "Per-DHCP-server: audit-log enabled flag, audit-log file path + size, database backup interval + path, last database cleanup. Out-of-the-box DHCP audit log is ENABLED but admins sometimes disable it for disk-space concerns - that erases the trail when an IP-conflict investigation happens later."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B4 DNS DHCP"
$Severity       = "P3"
$Recommendation = "Audit log MUST be enabled for compliance and forensic reasons. Database backup path should be on a different drive than the system drive. Backup interval default 60 minutes is fine."

if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
    [pscustomobject]@{ Note = 'DhcpServer module not available.' }; return
}
$servers = @()
if ($Global:DHCPServerList) { $servers = @($Global:DHCPServerList) }
else { try { $servers = @((Get-DhcpServerInDC -ErrorAction Stop).DnsName) } catch { } }
if ($servers.Count -eq 0) { return }

foreach ($s in $servers) {
    if (-not $s) { continue }
    try {
        $audit = Get-DhcpServerAuditLog -ComputerName $s -ErrorAction Stop
        $db    = Get-DhcpServerDatabase -ComputerName $s -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Server          = $s
            AuditLogEnabled = [bool]$audit.Enable
            AuditLogPath    = $audit.Path
            MaxLogFileSizeMB = $audit.MaxMBFileSize
            DiskFreeMB      = $audit.DiskCheckInterval
            DbPath          = if ($db) { $db.FileName } else { '' }
            DbBackupPath    = if ($db) { $db.BackupPath } else { '' }
            DbBackupInterval = if ($db) { $db.BackupInterval } else { '' }
            DbCleanupInterval = if ($db) { $db.CleanupInterval } else { '' }
        }
    } catch {
        [pscustomobject]@{ Server=$s; AuditLogEnabled=''; AuditLogPath=''; MaxLogFileSizeMB=''; DiskFreeMB=''; DbPath=''; DbBackupPath=''; DbBackupInterval=''; DbCleanupInterval=$_.Exception.Message }
    }
}

$TableFormat = @{
    AuditLogEnabled = { param($v,$row) if ($v -eq $true) { 'ok' } elseif ($v -eq $false) { 'bad' } else { '' } }
}
