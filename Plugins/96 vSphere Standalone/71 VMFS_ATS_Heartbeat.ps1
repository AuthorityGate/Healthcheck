# Start of Settings
# End of Settings

$Title          = 'VMFS ATS Heartbeat Setting'
$Header         = '[count] host(s) with VMFS3.UseATSForHBOnVMFS5 not set to default'
$Comments       = "KB 2113956: VMFS3.UseATSForHBOnVMFS5 controls whether ESXi uses Atomic Test and Set (ATS) for VMFS5 heartbeat. Default = 1 (use ATS) for arrays that support VAAI ATS. Some arrays have firmware bugs causing 'Lost access to volume' events; on those arrays only, set to 0."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Default is 1 (ATS heartbeat enabled). Only set to 0 if your array vendor has identified an ATS firmware bug; document the override for the next refresh.'

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $v = (Get-AdvancedSetting -Entity $h -Name 'VMFS3.UseATSForHBOnVMFS5' -ErrorAction SilentlyContinue).Value
    if ($null -ne $v -and [int]$v -ne 1) {
        [pscustomobject]@{
            Host                       = $h.Name
            UseATSForHBOnVMFS5         = $v
            Default                    = 1
            Note                       = 'ATS heartbeat disabled - confirm this matches an array-vendor advisory.'
        }
    }
}
