# Start of Settings
# End of Settings

$Title          = 'UAG Active Sessions'
$Header         = '[count] active session(s) on this UAG'
$Comments       = 'Snapshot of current sessions; useful capacity baseline.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '90 Gateways'
$Severity       = 'Info'
$Recommendation = 'Track over time; UAG default cap 4096 Horizon sessions per appliance.'

if (-not (Get-UAGRestSession)) { return }
try { $s = Get-UAGSession } catch { return }
if (-not $s) { return }
[pscustomobject]@{ ActiveSessions = if ($s.sessions) { @($s.sessions).Count } else { 0 } }
