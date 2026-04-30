# Start of Settings
# End of Settings

$Title          = 'vCenter Native VM Encryption'
$Header         = '[count] VM(s) using native vSphere encryption'
$Comments       = "Reference: 'Virtual Machine Encryption' (vCenter docs). Requires KMS cluster + storage policy."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'Info'
$Recommendation = 'Audit encrypted VMs vs compliance scope. Confirm KMS rotation schedule.'

if (-not $Global:VCConnected) { return }
Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.ExtensionData.Config.KeyId } | ForEach-Object {
    [pscustomobject]@{
        VM         = $_.Name
        KmsCluster = $_.ExtensionData.Config.KeyId.ProviderId.Id
        KeyId      = $_.ExtensionData.Config.KeyId.KeyId
    }
}
