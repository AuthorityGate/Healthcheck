# Start of Settings
# End of Settings

$Title          = 'Global Application Entitlements'
$Header         = '[count] global application entitlements'
$Comments       = "Reference: 'Configure Global Entitlements for Applications'. Application GEs span pods for published-app entitlements."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '20 Cloud Pod Architecture'
$Severity       = 'Info'
$Recommendation = 'Audit per global entitlement: members + scope policy + default protocol. Disable orphan entitlements.'

if (-not (Get-HVRestSession)) { return }
try { $ga = Invoke-HVRest -Path '/v1/global-application-entitlements' } catch { return }
if (-not $ga) { return }
foreach ($g in $ga) {
    [pscustomobject]@{
        Name             = $g.name
        Type             = $g.type
        Enabled          = $g.enabled
        ScopePolicy      = $g.scope_policy
        FromHome         = $g.from_home
        DefaultProtocol  = $g.default_display_protocol
    }
}

