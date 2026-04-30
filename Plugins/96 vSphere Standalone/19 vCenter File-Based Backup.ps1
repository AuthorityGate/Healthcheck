# Start of Settings
# End of Settings

$Title          = "vCenter File-Based Backup"
$Header         = "vCenter Server (VCSA) backup configuration / last status"
$Comments       = "Reference: 'VMware vCenter Server Installation and Setup' -> 'File-Based Backup'. VCSA must back up to FTP/SFTP/HTTP/SMB/NFS on a documented schedule. Without it, recovery from VAMI corruption / vmdir failure is rebuild-from-scratch."
$Display        = "List"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "VCSA VAMI (https://<vc>:5480) -> Backup -> 'Configure' (schedule + target). Test the restore path on a lab VCSA at least quarterly."

if (-not $Global:VCConnected) { return }
$vc = $global:DefaultVIServer
if (-not $vc) { return }

# Most VAMI APIs require a 5480 session token, not the vSphere SDK. We surface a guidance row plus the vCenter version so the user can act.
[pscustomobject]@{
    'vCenter'             = $vc.Name
    'Version / Build'     = "$($vc.Version) ($($vc.Build))"
    'Backup API endpoint' = "https://$($vc.Name):5480/#/appliance/recovery/backup"
    'Verification'        = 'PowerCLI cannot read VAMI backup state without a separate VAPI session - log in to VAMI to confirm schedule + last successful run.'
    'Reference'           = 'KB 2147541 / VCSA Backup and Restore'
}
