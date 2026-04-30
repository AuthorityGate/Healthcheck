# Start of Settings
# End of Settings

$Title          = 'Active Sessions vs Licensed CCU'
$Header         = 'Concurrent session usage vs license entitlement'
$Comments       = 'Subscription licenses cap by named user OR CCU. Sustained > 90% of CCU == buy more licenses or risk auth failures.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '60 Sessions'
$Severity       = 'P2'
$Recommendation = "Compare 'currentSessionCount' from license endpoint with subscribed CCU; raise quota or invoke true-up."

if (-not (Get-HVRestSession)) { return }
$s = Get-HVSession
$lic = Get-HVLicense
if (-not $s -or -not $lic) { return }
[pscustomobject]@{
    ActiveSessions          = $s.Count
    LicensedCCU             = $lic.subscribed_ccu
    SessionsPercentOfCCU    = if ($lic.subscribed_ccu -gt 0) { [math]::Round(($s.Count / $lic.subscribed_ccu) * 100, 1) } else { 'n/a' }
    UsageModel              = $lic.usage_model
}

