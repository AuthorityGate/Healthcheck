# Start of Settings
$MaxAppsRendered = 500
# End of Settings

$Title          = "vIDM Application Catalog"
$Header         = "[count] application(s) in the catalog (capped at $MaxAppsRendered)"
$Comments       = "Every application configured for the catalog: SaaS apps (SAML / OIDC / WS-Fed), Horizon resources, Citrix, ThinApp, web links. Includes federation type, auth profile, entitled-group count. Used for upgrade planning + SAML-cert-rotation impact mapping."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B5 Workspace ONE Access"
$Severity       = "Info"
$Recommendation = "Apps with stale signing certs (>1 year) should be rotated. Apps with no entitlement = orphans, candidate for removal. Apps using IdP-Initiated SSO without SP-Initiated risk being unreachable when vIDM has an outage."

if (-not (Get-VIDMRestSession)) { return }
$apps = $null
try { $apps = Get-VIDMApplication } catch { }
if (-not $apps -or -not $apps.items) {
    [pscustomobject]@{ Note = 'No applications returned (or insufficient scope on the OAuth client).' }
    return
}

$rendered = 0
foreach ($a in $apps.items) {
    if ($rendered -ge $MaxAppsRendered) { break }
    [pscustomobject]@{
        Name          = $a.name
        Type          = $a.applicationType
        AuthProtocol  = $a.authInfo.authMethod
        Description   = if ($a.description) { $a.description.Substring(0,[Math]::Min(80,$a.description.Length)) } else { '' }
        EntityId      = $a.authInfo.entityID
        IdpInitiated  = [bool]$a.authInfo.targetURL
        Categories    = if ($a.categories) { ($a.categories -join ', ') } else { '' }
        Activated     = [bool]$a.activated
    }
    $rendered++
}

$TableFormat = @{
    Activated = { param($v,$row) if ($v -eq $true) { 'ok' } else { 'warn' } }
}
