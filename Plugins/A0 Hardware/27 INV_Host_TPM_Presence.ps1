# Start of Settings
# End of Settings

$Title          = 'Host TPM Presence'
$Header         = 'Per-host TPM 2.0 device state'
$Comments       = 'TPM 2.0 is required for vSphere Native Key Provider, attestation, secure boot. Hosts without TPM cannot enroll VMs into encryption-by-policy.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'Info'
$Recommendation = 'If TPM is missing on a host destined for VM Encryption / Win11 vTPM, schedule a hardware refresh.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    $tpm = $h.ExtensionData.Capability.TpmSupported
    $attest = $h.ExtensionData.Runtime.TpmAttestation
    [pscustomobject]@{
        Host           = $h.Name
        TpmSupported   = $tpm
        AttestationAlgorithm = if ($attest) { $attest.AttestationAlgorithm } else { 'n/a' }
        TpmState       = if ($attest) { $attest.Status } else { 'n/a' }
    }
}
