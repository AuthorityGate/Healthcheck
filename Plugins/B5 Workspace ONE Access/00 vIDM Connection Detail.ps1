# Start of Settings
# End of Settings

$Title          = "vIDM Connection Detail + System Info"
$Header         = "Workspace ONE Access tenant + version + connector summary"
$Comments       = "First plugin in the vIDM scope. Validates the OAuth bearer token, dumps tenant version + build, and counts connectors / directories so the operator immediately sees whether the calling client has read access to the surface this audit needs."
$Display        = "List"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B5 Workspace ONE Access"
$Severity       = "Info"
$Recommendation = "If 'Tenant Version' is empty or 'Connectors' is 0, the OAuth client lacks the Admin scope. Re-bind the client with the 'Admin Read' role under Catalog -> Settings -> Remote App Access."

$s = Get-VIDMRestSession
if (-not $s) {
    [pscustomobject]@{ Status = '(not connected)'; Note = 'vIDM plugins skip. Set OAuth client + secret on the vIDM tab.' }
    return
}

$info = Get-VIDMSystemInfo
$health = Get-VIDMHealth
$conns = @(Get-VIDMConnector)
$dirs  = @(Get-VIDMDirectory)
$tenants = Get-VIDMTenantConfig

[pscustomobject]@{
    'Tenant FQDN'    = $s.Server
    'Tenant Path'    = $s.TenantPath
    'Connected At'   = $s.ConnectedAt
    'Tenant Version' = if ($info) { $info.version } else { '(no /system/info data)' }
    'Tenant Build'   = if ($info) { $info.build } else { '' }
    'Health'         = if ($health) { $health.status } else { '' }
    'Connector count'= $conns.Count
    'Directory count'= $dirs.Count
    'Tenant ID'      = if ($tenants -and $tenants.id) { $tenants.id } else { '' }
}
