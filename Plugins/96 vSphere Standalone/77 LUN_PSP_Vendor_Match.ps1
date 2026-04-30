# Start of Settings
# Vendor-recommended Path Selection Policy (KB 1011340 + per-array vendor docs).
# This is a curated heuristic; consult your array's official guide for production.
$VendorPSP = @{
    'DGC'     = 'VMW_PSP_RR'   # Dell EMC CLARiiON / VNX classic
    'EMC'     = 'VMW_PSP_RR'   # Dell EMC PowerMax / VMAX (round-robin recommended)
    'COMPELNT'= 'VMW_PSP_RR'   # Dell Compellent
    'HITACHI' = 'VMW_PSP_RR'   # Hitachi VSP
    'HP'      = 'VMW_PSP_RR'   # HPE 3PAR / Primera (round-robin with IOPS=1)
    'NETAPP'  = 'VMW_PSP_RR'   # NetApp ONTAP
    'PURE'    = 'VMW_PSP_RR'   # Pure FlashArray
    'IBM'     = 'VMW_PSP_RR'   # IBM SVC/Storwize
    'NIMBLE'  = 'VMW_PSP_RR'
    'NEXGEN'  = 'VMW_PSP_RR'
}
# End of Settings

$Title          = 'LUN Path Selection Policy vs Vendor Recommendation'
$Header         = '[count] LUN(s) with non-recommended PSP'
$Comments       = "VMware claim rules + per-array Storage Array Type Plug-In dictate the recommended Path Selection Policy. Most modern arrays want VMW_PSP_RR (round-robin), often with iops=1 sub-policy. MRU or Fixed on a modern AFA underutilizes paths and burns one HBA at a time."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = "esxcli storage nmp psp set --device <NAA> --psp VMW_PSP_RR. Then for round-robin sub-policy: esxcli storage nmp psp roundrobin deviceconfig set --device <NAA> --type=iops --iops=1 (verify with vendor doc)."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $luns = Get-ScsiLun -VmHost $h -LunType disk -ErrorAction SilentlyContinue
        foreach ($l in $luns) {
            $vendor = ($l.Vendor + '').ToUpper().Trim()
            $expected = if ($VendorPSP.ContainsKey($vendor)) { $VendorPSP[$vendor] } else { $null }
            if ($expected -and $l.MultipathPolicy -ne 'RoundRobin') {
                [pscustomobject]@{
                    Host     = $h.Name
                    LUN      = $l.CanonicalName
                    Vendor   = $vendor
                    Model    = $l.Model
                    PSP      = $l.MultipathPolicy
                    Expected = 'RoundRobin'
                }
            }
        }
    } catch { }
}

$TableFormat = @{
    PSP = { param($v,$row) if ($v -ne 'RoundRobin') { 'warn' } else { '' } }
}
