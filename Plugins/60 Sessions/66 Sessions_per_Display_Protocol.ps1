# Start of Settings
# End of Settings

$Title          = 'Sessions per Display Protocol'
$Header         = 'Distribution of active sessions by protocol (BLAST/PCoIP/RDP)'
$Comments       = 'Mostly-PCoIP deployments are end-of-feature; BLAST is recommended.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '60 Sessions'
$Severity       = 'Info'
$Recommendation = 'Migrate pools default protocol to BLAST. Verify TCP+UDP firewall rules permit Blast Extreme Adaptive Transport (BEAT).'

if (-not (Get-HVRestSession)) { return }
$s = Get-HVSession
if (-not $s) { return }
$s | Group-Object session_protocol | ForEach-Object {
    [pscustomobject]@{ Protocol=$_.Name; Count=$_.Count }
}
