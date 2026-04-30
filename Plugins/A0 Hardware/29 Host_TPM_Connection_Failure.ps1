# Start of Settings
# End of Settings

$Title          = 'ESXi TPM 2.0 Connection Failure'
$Header         = "[count] host(s) with 'TPM 2.0 detected but connection cannot be established'"
$Comments       = "Reference: KB 87242. The vSphere Client raises 'TPM 2.0 device detected but a connection cannot be established' when ESXi sees a TPM chip in hardware but cannot complete attestation handshake. Common causes: TPM not enabled in BIOS, TPM cleared without re-provisioning, ESXi build does not match the TPM firmware level, Secure Boot disabled, or dirty NV index from a prior install. Without an attested TPM you lose: Native Key Provider host attestation, vTPM key-sealing for Win11/encrypted VMs, Secure Boot validation, and the vCenter trust-authority chain."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'P1'
$Recommendation = "1) Confirm Secure Boot is enabled in host BIOS. 2) Confirm TPM 2.0 is enabled and not 'hidden' in BIOS. 3) Reboot the host and re-check attestation. 4) If still failing, clear the TPM in BIOS (vendor procedure - does NOT impact running VMs but does invalidate any sealed keys), reboot, and re-attest. 5) Verify ESXi build is on Broadcom HCL for that server's TPM firmware. 6) Last resort: rebuild the ESXi install on that host."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue)) {
    if ($h.ConnectionState -ne 'Connected') { continue }

    $caps = $null
    $att  = $null
    try {
        $caps = $h.ExtensionData.Capability
        $att  = $h.ExtensionData.Runtime.TpmAttestation
    } catch { }

    $tpmPresent = if ($caps -and ($null -ne $caps.TpmSupported)) { [bool]$caps.TpmSupported } else { $false }
    if (-not $tpmPresent) { continue }   # No TPM at all - separate inventory plugin handles that.

    # Read attestation status. Possible Status values (from vSphere docs):
    #   pass / passed       = good
    #   warning             = degraded but operating
    #   fail / disconnected = the one we are looking for ("connection cannot be established")
    #   ''  / null          = TPM detected, never attested (also surfaces the same alarm)
    $statusKey  = if ($att -and $att.AttestationStatus) { [string]$att.AttestationStatus } elseif ($att -and $att.Status) { [string]$att.Status } else { '' }
    $statusText = if ($att -and $att.Message) { $att.Message } else { '' }
    $algo       = if ($att -and $att.AttestationAlgorithm) { $att.AttestationAlgorithm } else { 'n/a' }

    $isFailed = (-not $att) -or
                ($statusKey -eq '') -or
                ($statusKey -match 'fail|disconnect|error|notInitialized')
    $isWarning = $statusKey -match 'warning|degraded'

    if ($isFailed -or $isWarning) {
        # Try to fetch TPM version (1.2 vs 2.0). 2.0 is the impactful one.
        $tpmVer = if ($caps -and $caps.TpmVersion) { $caps.TpmVersion } else { '(unknown)' }
        [pscustomobject]@{
            Host                = $h.Name
            Cluster             = if ($h.Parent) { $h.Parent.Name } else { '' }
            TpmVersion          = $tpmVer
            AttestationStatus   = if ($statusKey) { $statusKey } else { '(no attestation)' }
            Algorithm           = $algo
            Detail              = if ($statusText) { $statusText } else { 'TPM device detected but connection / attestation has not been established.' }
            HostBuild           = "$($h.Version) build $($h.Build)"
            FixOrder            = '1) BIOS Secure Boot + TPM enabled  2) Reboot  3) Clear TPM in BIOS  4) Reattest  5) HCL check  6) Re-image'
        }
    }
}

$TableFormat = @{
    AttestationStatus = { param($v,$row) if ($v -match 'fail|disconnect|error|no attestation') { 'bad' } elseif ($v -match 'warning|degraded') { 'warn' } else { '' } }
}
