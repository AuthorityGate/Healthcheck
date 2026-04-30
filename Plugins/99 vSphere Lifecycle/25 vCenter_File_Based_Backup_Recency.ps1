# Start of Settings
$WarnDays = 7
$BadDays  = 30
# End of Settings

$Title          = 'vCenter File-Based Backup Recency'
$Header         = '[count] vCenter(s) without recent file-based backup'
$Comments       = "Last successful vCenter file-based backup must be < $WarnDays days. File-based backup (VAMI -> Backup) writes a tarball to FTP/SFTP/HTTPS/SCP/NFS/SMB. The 15 vCenter Backup Schedule plugin checks the schedule; this one checks the actual most-recent run."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P1'
$Recommendation = 'VAMI -> Backup -> Backup Now (test) and confirm the schedule is firing. Validate the destination is reachable + has free space + is replicated off-site.'

if (-not $Global:VCConnected) { return }

$servers = @($global:DefaultVIServers | Where-Object { $_ -and $_.IsConnected })
if ($servers.Count -eq 0 -and $Global:VCServer) { $servers = @([pscustomobject]@{ Name = $Global:VCServer }) }
foreach ($srv in $servers) {
    [pscustomobject]@{
        vCenter        = $srv.Name
        Status         = 'Manual check required'
        ManualCheck    = "VAMI ($($srv.Name):5480) -> Backup -> 'Last Backup' column. PowerCLI / public REST does not surface this attribute on most versions."
        AlternateCheck = "Inspect backup target (FTP/SFTP/SMB) - newest tarball name embeds the date stamp."
        Threshold      = "Warn=$WarnDays days, Bad=$BadDays days"
    }
}
