# Start of Settings
# End of Settings

$Title          = 'vSAN Encryption State'
$Header         = '[count] vSAN cluster(s) with encryption enabled'
$Comments       = "Reference: 'vSAN Encryption' (VMware docs). Required for HIPAA / DoD; KMS server bound."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'P2'
$Recommendation = 'Confirm KMS health; rotate the KEK annually.'

if (-not $Global:VCConnected) { return }
Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.VsanEnabled } | ForEach-Object {
    $cfg = $_.ExtensionData.ConfigurationEx.VsanConfigInfo.DataEncryptionConfig
    [pscustomobject]@{
        Cluster      = $_.Name
        EncryptionEnabled = if ($cfg) { $cfg.EncryptionEnabled } else { $false }
        KmsClusterId = if ($cfg) { $cfg.KmsProviderId.Id } else { '' }
    }
}
