# Start of Settings
# End of Settings

$Title          = 'Host TPM 2.0 Firmware Drift'
$Header         = '[count] host(s) with TPM 2.0 firmware versions inventory'
$Comments       = "Per-host TPM 2.0 firmware version. vTPM stamping uses host TPM as a hardware root of trust. Inconsistent firmware across the cluster won't block boot but can cause vTPM Attestation drift after vMotion."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'P3'
$Recommendation = 'Apply vendor firmware updates via vLCM. Sync host TPM firmware across all hosts in any cluster that hosts vTPM-equipped VMs.'

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $hv = $h | Get-View -Property 'Capability','Hardware','Runtime' -ErrorAction Stop
        $tpmAttest = $hv.Runtime.TpmAttestation
        $hasTpm = $hv.Capability.TpmSupported
        if ($hasTpm) {
            [pscustomobject]@{
                Host           = $h.Name
                TpmSupported   = $true
                TpmVersion     = if ($tpmAttest) { $tpmAttest.TpmVersion } else { '' }
                AttestationStatus = if ($tpmAttest) { $tpmAttest.AttestationStatus } else { '' }
                ManufacturerId = if ($tpmAttest) { $tpmAttest.ManufacturerId } else { '' }
            }
        }
    } catch { }
}
