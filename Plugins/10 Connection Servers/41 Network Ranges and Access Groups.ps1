# Start of Settings
# End of Settings

$Title          = "Network Ranges and Access Groups"
$Header         = "[count] network range / access group object(s)"
$Comments       = "Horizon uses network ranges and access groups to scope policy (which users can connect from which IPs to which pools). Inventory includes restricted-tag mappings used for UAG vs internal-only segregation."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "10 Connection Servers"
$Severity       = "Info"
$Recommendation = "Validate that DMZ-facing UAG sessions are tagged and that internal-only pools use restricted tags to enforce segregation. Network ranges that overlap should be consolidated."

if (-not (Get-HVRestSession)) { return }

$ranges = @(Get-HVNetworkRange)
$groups = @(Get-HVAccessGroup)
$tags   = @(Get-HVRestrictedTag)

foreach ($r in $ranges) {
    [pscustomobject]@{
        Type       = 'NetworkRange'
        Name       = $r.name
        Detail     = "$($r.start_ipv4) -> $($r.end_ipv4) | tag=$($r.tag)"
        Description= $r.description
    }
}
foreach ($g in $groups) {
    [pscustomobject]@{
        Type       = 'AccessGroup'
        Name       = $g.name
        Detail     = "Parent=$($g.parent_id) | Members=$(@($g.member_ids).Count)"
        Description= $g.description
    }
}
foreach ($t in $tags) {
    [pscustomobject]@{
        Type       = 'RestrictedTag'
        Name       = $t.name
        Detail     = "Pools=$(@($t.desktop_pool_ids).Count) | Farms=$(@($t.farm_ids).Count) | AppPools=$(@($t.application_pool_ids).Count)"
        Description= $t.description
    }
}
