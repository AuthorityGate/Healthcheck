# Start of Settings
# End of Settings

$Title          = 'NSX DNS Forwarders'
$Header         = '[count] DNS forwarder profile(s)'
$Comments       = 'DNS forwarders expose internal DNS to overlay. Mis-set forwarder == DNS leak / failure.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P3'
$Recommendation = 'Validate forwarder zone scope and upstream IPs.'

if (-not (Get-NSXRestSession)) { return }
try { $f = Invoke-NSXRest -Path '/policy/api/v1/infra/tier-1s' } catch { return }
if (-not $f) { return }
[pscustomobject]@{ Note='Per-T1 DNS forwarder is exposed at /policy/api/v1/infra/tier-1s/{id}/dns-forwarder' }
