# Start of Settings
# End of Settings

$Title          = 'iSCSI CHAP Authentication'
$Header         = '[count] iSCSI HBA target(s) NOT using CHAP'
$Comments       = "iSCSI traffic without CHAP authentication is plain-text on the data plane. CHAP (one-way or mutual) prevents unauthorized initiators from binding to your storage. Mutual CHAP additionally protects against rogue target masquerade."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Host -> Configure -> Storage Adapters -> iSCSI HBA -> Authentication -> Edit -> CHAP. Configure on the array side first; rotate CHAP passwords periodically.'

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $hbas = @(Get-VMHostHba -VMHost $h -Type IScsi -ErrorAction SilentlyContinue)
    foreach ($hba in $hbas) {
        try {
            $auth = $hba.AuthenticationProperties
            $chapType = if ($auth) { $auth.ChapType } else { 'unknown' }
            if ($chapType -eq 'chapProhibited' -or $chapType -eq 'chapDiscouraged') {
                [pscustomobject]@{
                    Host       = $h.Name
                    HBA        = $hba.Name
                    Model      = $hba.Model
                    ChapType   = $chapType
                    MutualChap = if ($auth) { $auth.MutualChapType } else { '' }
                }
            }
        } catch { }
    }
}

$TableFormat = @{
    ChapType = { param($v,$row) if ($v -match 'Prohibited|Discouraged') { 'warn' } else { '' } }
}
