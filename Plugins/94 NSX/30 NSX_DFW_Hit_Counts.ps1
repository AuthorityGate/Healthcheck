# Start of Settings
# End of Settings

$Title          = 'NSX DFW Rule Hit Count Audit'
$Header         = "[count] DFW rule(s) with zero hits in 90 days"
$Comments       = "DFW rules with sustained zero hits = candidates for removal. Either the policy never matches (logic error) or the rule is dead. Curating these removes ACL bloat."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P3'
$Recommendation = "Review zero-hit rules. Remove or document the business reason. Periodic curation keeps the rule set minimal + auditable."

if (-not (Get-NSXRestSession)) { return }

try {
    # NSX Policy API: get DFW rules with stats
    $policies = Invoke-NSXRest -Path '/policy/api/v1/infra/domains/default/security-policies' -Method GET
    foreach ($pol in @($policies.results)) {
        $rules = Invoke-NSXRest -Path "/policy/api/v1/infra/domains/default/security-policies/$($pol.id)/rules" -Method GET
        foreach ($r in @($rules.results)) {
            try {
                $stats = Invoke-NSXRest -Path "/policy/api/v1/infra/domains/default/security-policies/$($pol.id)/rules/$($r.id)/statistics" -Method GET
                $hits = 0
                if ($stats -and $stats.results) {
                    foreach ($s in $stats.results) { $hits += [int]$s.hit_count }
                }
                if ($hits -eq 0) {
                    [pscustomobject]@{
                        Section = $pol.display_name
                        Rule    = $r.display_name
                        Action  = $r.action
                        Sources = if ($r.source_groups) { ($r.source_groups | Select-Object -First 3) -join '; ' } else { 'ANY' }
                        Destinations = if ($r.destination_groups) { ($r.destination_groups | Select-Object -First 3) -join '; ' } else { 'ANY' }
                        Services = if ($r.services) { ($r.services | Select-Object -First 3) -join '; ' } else { 'ANY' }
                        HitCount = $hits
                        Note     = 'Zero-hit rule - candidate for review'
                    }
                }
            } catch { continue }
        }
    }
} catch { }

$TableFormat = @{
    HitCount = { param($v,$row) if ($v -eq 0) { 'warn' } else { '' } }
}
