# Start of Settings
# End of Settings

$Title          = 'Application Pool Anti-Affinity'
$Header         = '[count] application pool(s) without anti-affinity rules'
$Comments       = "Reference: 'Configure Anti-affinity Rules for Application Pools'. Without rules, multiple instances of the same chunky app (Office, Chrome) can pile on one host."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '40 RDS Farms'
$Severity       = 'P3'
$Recommendation = "Edit pool -> Anti-affinity -> set affinity pattern (e.g., '*chrome*=2,*excel*=2')."

if (-not (Get-HVRestSession)) { return }
$apps = Get-HVApplicationPool
if (-not $apps) { return }
foreach ($a in $apps) {
    if (-not $a.anti_affinity_patterns) {
        [pscustomobject]@{ App=$a.name; Farm=$a.farm_name; AntiAffinity='(none)' }
    }
}

