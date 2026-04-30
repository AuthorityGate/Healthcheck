# Start of Settings
# End of Settings

$Title          = 'Host Profile Compliance'
$Header         = '[count] host(s) non-compliant against attached host profile'
$Comments       = 'Host profile drift indicates manual configuration changes. Triggers configuration churn.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P3'
$Recommendation = "Remediate via 'Check Host Profile Compliance' then 'Remediate'."

if (-not $Global:VCConnected) { return }
$profs = Get-VMHostProfile -ErrorAction SilentlyContinue
if (-not $profs) { return }
foreach ($p in $profs) {
    foreach ($h in (Get-VMHost -Location * -ErrorAction SilentlyContinue)) {
        try {
            $r = Test-VMHostProfileCompliance -VMHost $h -Profile $p -ErrorAction SilentlyContinue
            if ($r.Status -ne 'compliant') {
                [pscustomobject]@{ Host=$h.Name; Profile=$p.Name; Status=$r.Status }
            }
        } catch { }
    }
}
