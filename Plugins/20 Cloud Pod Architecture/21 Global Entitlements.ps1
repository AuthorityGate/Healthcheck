# Start of Settings
# End of Settings

$Title          = "Global Entitlements"
$Header         = "[count] global entitlement(s)"
$Comments       = "Global entitlements span pods. Verify scope policy + member pool count for each entitlement."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "20 Cloud Pod Architecture"
$Severity       = "Info"

$ge = Get-HVGlobalEntitlement
if (-not $ge) { return }

foreach ($g in $ge) {
    [pscustomobject]@{
        Name             = $g.name
        Type             = $g.type
        ScopePolicy      = $g.scope_policy
        FromHomeSite     = $g.from_home
        MemberPools      = if ($g.local_member_count) { $g.local_member_count } else { 0 }
        Enabled          = $g.enabled
        DefaultProtocol  = $g.default_display_protocol
    }
}

$TableFormat = @{
    Enabled = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
}
