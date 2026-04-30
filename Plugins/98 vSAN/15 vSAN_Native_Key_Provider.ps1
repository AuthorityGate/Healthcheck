# Start of Settings
# End of Settings

$Title          = 'vSAN Native Key Provider State'
$Header         = "vSAN Native Key Provider configuration"
$Comments       = "Native Key Provider (NKP) provides encryption keys for vSAN encryption + vTPM without external KMS. Simpler than external KMS for non-FIPS scenarios. Surfaces NKP state per vCenter."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'P3'
$Recommendation = "For non-FIPS deployments wanting vSAN encryption + Win11 vTPM, configure Native Key Provider in vCenter. Backup NKP state. For FIPS or sovereign-key requirements, use external KMS instead."

if (-not $Global:VCConnected) { return }

try {
    $vc = $Global:DefaultVIServer
    if (-not $vc) {
        [pscustomobject]@{ KeyProvider='(no vCenter)'; State=''; Note='No vCenter session.' }
        return
    }
    $kpManager = Get-View ($vc.ExtensionData.Content.CryptoManager)
    if (-not $kpManager) {
        [pscustomobject]@{ KeyProvider='(none)'; State=''; Note='No Crypto Manager - no Key Providers configured.' }
        return
    }
    $kpList = $kpManager.ListKmipServers($null)
    if (-not $kpList -or @($kpList).Count -eq 0) {
        [pscustomobject]@{ KeyProvider='(none)'; State=''; Note='No Key Providers configured. NKP setup: vCenter -> Configure -> Key Providers -> Add -> Native Key Provider.' }
        return
    }
    foreach ($kp in @($kpList)) {
        [pscustomobject]@{
            KeyProvider  = $kp.ClusterId.Id
            ServerCount  = if ($kp.Servers) { @($kp.Servers).Count } else { 0 }
            UseAsDefault = $kp.UseAsDefault
            State        = 'Configured'
            Note         = ''
        }
    }
} catch {
    [pscustomobject]@{ KeyProvider = 'Error'; State = ''; Note = $_.Exception.Message }
}
