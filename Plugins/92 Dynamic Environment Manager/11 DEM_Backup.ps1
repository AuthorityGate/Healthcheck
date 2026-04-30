# Start of Settings
# End of Settings

$Title          = 'DEM Backup'
$Header         = 'DEM config-share snapshot / backup'
$Comments       = 'DEM stores admin-authored configs in a SMB share. Backup is a manual / SCM-driven step.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P2'
$Recommendation = 'Schedule a daily backup of the config share to versioned storage. Test restore quarterly.'

$share = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware UEM\Agent\FlexEngine' -ErrorAction SilentlyContinue).ConfigShare
if (-not $share) { return }
[pscustomobject]@{
    ConfigShare        = $share
    AutomatedBackup    = 'Verify manually - DEM has no built-in backup'
    Reference          = 'Omnissa DEM Admin Guide -> Backing up FlexEngine'
}
