# Start of Settings
# End of Settings

$Title          = "vIDM Directory Bindings (AD / LDAP)"
$Header         = "[count] directory binding(s)"
$Comments       = "Every directory that vIDM is bound to: type (AD over LDAP, AD over IWA, plain LDAP, JIT, Local), domain, sync-on-demand mode, last-sync timestamp, total user count, total group count. Failed sync = silent SAML auth degradation."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B5 Workspace ONE Access"
$Severity       = "P2"
$Recommendation = "Sync gaps over 24h indicate a connector communication or service-account credential issue. Verify the bind account hasn't expired and TLS certs on the connector are still valid."

if (-not (Get-VIDMRestSession)) { return }
$dirs = @(Get-VIDMDirectory)
if ($dirs.Count -eq 0) {
    [pscustomobject]@{ Note = 'No directory bindings returned (or the OAuth client lacks Admin Read scope).' }
    return
}

foreach ($d in $dirs) {
    [pscustomobject]@{
        Name           = $d.name
        Type           = $d.type
        Domain         = if ($d.domains) { ($d.domains -join ', ') } else { '' }
        SyncMode       = $d.userAttributeMappings
        LastSyncEnded  = $d.lastSyncEndTime
        UsersCount     = $d.usersCount
        GroupsCount    = $d.groupsCount
        SyncEnabled    = [bool]$d.syncEnabled
        ConnectorName  = if ($d.directoryConfigurations) { ($d.directoryConfigurations | ForEach-Object { $_.connectorName }) -join ', ' } else { '' }
    }
}

$TableFormat = @{
    SyncEnabled = { param($v,$row) if ($v -eq $true) { 'ok' } else { 'warn' } }
}
