# Start of Settings
# End of Settings

$Title          = 'App Volumes Domain Configuration'
$Header         = '[count] domain(s) registered'
$Comments       = 'AV requires the AD domain controller list for SID resolution. Stale entries slow logon.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P2'
$Recommendation = 'AV Console -> Configuration -> Domains. Remove decommissioned DCs.'

if (-not (Get-AVRestSession)) { return }
try { $d = Invoke-AVRest -Path '/cv_api/domains' } catch { return }
if (-not $d) { return }
foreach ($x in $d.domains) {
    [pscustomobject]@{ Name=$x.name; Type=$x.directory_type; Default=$x.default; ReplicaCount=if ($x.replicas) { @($x.replicas).Count } else { 0 } }
}
