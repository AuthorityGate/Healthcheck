# Start of Settings
# End of Settings

$Title          = "Horizon REST Schema Snapshot"
$Header         = "Property keys returned by each Horizon REST endpoint"
$Comments       = @"
Hits each well-known Horizon REST endpoint, takes the FIRST object in the response, and lists its property names. Used to verify which schema variant the connected Connection Server returns - flat (pre-2206 - properties at top level) versus nested (2206+ - many fields under .details or .general). The runner auto-flattens nested-details up to the top level, so plugins keep working either way; this snapshot exists so an operator can confirm what the API actually returned. Empty 'TopLevelKeys' for a row means the endpoint returned no objects (zero items, not a schema problem).
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "00 Initialize"
$Severity       = "Info"
$Recommendation = "If a plugin shows empty cells but its row count is > 0, compare the property names listed here to what the plugin reads. Report the diff to AuthorityGate so the helper can be widened."

if (-not (Get-HVRestSession)) {
    [pscustomobject]@{ Endpoint = '(no Horizon session)'; TopLevelKeys = ''; NestedKeys = '' }
    return
}

$endpoints = @(
    @{ Label = 'connection-servers';  Path = '/v1/monitor/connection-servers' }
    @{ Label = 'virtual-centers';     Path = '/v1/monitor/virtual-centers' }
    @{ Label = 'gateways';            Path = '/v1/monitor/gateways' }
    @{ Label = 'pods';                Path = '/v1/pods' }
    @{ Label = 'sites';               Path = '/v1/sites' }
    @{ Label = 'desktop-pools';       Path = '/v2/desktop-pools' }
    @{ Label = 'farms';               Path = '/v1/farms' }
    @{ Label = 'application-pools';   Path = '/v1/application-pools' }
    @{ Label = 'machines';            Path = '/v1/machines' }
    @{ Label = 'rds-servers';         Path = '/v1/rds-servers' }
    @{ Label = 'sessions';            Path = '/v1/sessions' }
    @{ Label = 'global-entitlements'; Path = '/v1/global-entitlements' }
)

foreach ($e in $endpoints) {
    $items = $null
    try { $items = Invoke-HVRest -Path $e.Path -ErrorAction SilentlyContinue } catch { }
    $count = @($items).Count
    if ($count -eq 0) {
        [pscustomobject]@{
            Endpoint     = $e.Label
            ItemCount    = 0
            TopLevelKeys = '(no objects returned)'
            NestedKeys   = ''
        }
        continue
    }
    $snap = Get-HVSchemaSnapshot -Items $items
    [pscustomobject]@{
        Endpoint     = $e.Label
        ItemCount    = $count
        TopLevelKeys = if ($snap) { $snap.TopLevelKeys } else { '' }
        NestedKeys   = if ($snap) { $snap.NestedKeys }   else { '' }
    }
}
