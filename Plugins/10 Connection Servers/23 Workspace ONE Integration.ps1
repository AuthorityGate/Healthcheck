# Start of Settings
# End of Settings

$Title          = 'Workspace ONE Access Integration'
$Header         = 'Workspace ONE Access (Identity Manager) connection state'
$Comments       = "Reference: 'Configure Workspace ONE Access in Horizon Console' (Horizon docs). When integrated, all auth flows through WS1; if the WS1 cert chain is invalid, all logons fail."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'P2'
$Recommendation = 'Verify WS1 hostname, public-cert chain, and Identity Manager URL on Settings -> Servers -> Connection Servers -> Authentication.'

if (-not (Get-HVRestSession)) { return }
try { $w1 = Invoke-HVRest -Path '/v1/config/workspace-one' -NoPaging } catch { return }
if (-not $w1) { return }
[pscustomobject]@{
    Enabled         = $w1.enabled
    Hostname        = $w1.hostname
    Blocked         = $w1.block_horizon_console_access_in_workspace_one
    DelegatedAuth   = $w1.allow_delegated_authentication
}

