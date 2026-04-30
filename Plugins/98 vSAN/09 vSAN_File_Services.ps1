# Start of Settings
# End of Settings

$Title          = 'vSAN File Services'
$Header         = '[count] cluster(s) with vSAN File Services enabled'
$Comments       = 'vSAN File Services exposes NFS / SMB shares from the cluster. Useful for user-profile shares.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'Info'
$Recommendation = 'Verify file-services VMs are healthy and the share endpoint is reachable.'

if (-not $Global:VCConnected) { return }
Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.VsanEnabled } | ForEach-Object {
    $fs = $_.ExtensionData.ConfigurationEx.VsanConfigInfo.FileServiceConfig
    if ($fs -and $fs.Enabled) {
        [pscustomobject]@{ Cluster=$_.Name; FileServicesEnabled=$true; Domain=$fs.Domains.Domain }
    }
}
