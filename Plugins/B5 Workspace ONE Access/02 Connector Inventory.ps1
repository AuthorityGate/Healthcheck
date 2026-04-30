# Start of Settings
# End of Settings

$Title          = "vIDM Connector Inventory"
$Header         = "[count] vIDM connector(s) registered"
$Comments       = "Connectors are the on-prem agents that bridge the SaaS / on-prem vIDM tenant to AD, RSA, RADIUS, etc. Each connector's version + last-heartbeat + auth-method bindings shown."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B5 Workspace ONE Access"
$Severity       = "P2"
$Recommendation = "Connectors not heard from in 30+ minutes are de-facto failed. Older connector versions (more than 12 months behind tenant) get fewer fixes - schedule upgrade. Two connectors per site is the minimum for HA; a single connector is a SPOF."

if (-not (Get-VIDMRestSession)) { return }
$conns = @(Get-VIDMConnector)
if ($conns.Count -eq 0) {
    [pscustomobject]@{ Note = 'No connectors visible (or insufficient OAuth scope).' }
    return
}

foreach ($c in $conns) {
    [pscustomobject]@{
        Name              = $c.name
        Hostname          = $c.hostName
        Version           = $c.version
        Build             = $c.build
        State             = $c.state
        LastHeartbeat     = $c.lastUpdated
        AuthAdapters      = if ($c.authAdapterTypes) { ($c.authAdapterTypes -join ', ') } else { '' }
        LdapDirectories   = if ($c.ldapDirectoriesIds) { @($c.ldapDirectoriesIds).Count } else { 0 }
    }
}

$TableFormat = @{
    State = { param($v,$row) if ($v -match 'enabled|active|connected') { 'ok' } elseif ($v) { 'warn' } else { '' } }
}
