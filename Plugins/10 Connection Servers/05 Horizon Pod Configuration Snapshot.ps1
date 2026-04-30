# Start of Settings
# End of Settings

$Title          = 'Horizon Pod Configuration Snapshot'
$Header         = 'Rebuild-grade configuration capture across every reachable Horizon REST endpoint'
$Comments       = @"
Comprehensive sweep of every Horizon REST configuration endpoint reachable on this build. Each row is one settings group with the count of items returned and a summary of fields present. Use this as the source-of-truth for a "rebuild identical" project: every configured authenticator, vCenter binding, certificate, license, network range, RADIUS / SAML / smart-card settings, helpdesk role, gateway, true-SSO, persistent-disk policy, restricted-tag, event-DB binding, recovery setting, and admin-role-mapping that the API exposes.

Fields with no data on the connected Horizon build (404 or empty response) are listed under 'Skipped' so the consultant knows which features are NOT in use vs which are simply not exposed by this version's REST surface.
"@
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'Info'
$Recommendation = 'Use this snapshot to rebuild an identical pod: each Group row tells you which feature is configured, how many items, and the field set returned. Cross-reference with Horizon Console -> Settings to confirm parity. Skipped rows = either feature not used on this pod OR the REST surface on this Horizon build does not expose it (Swagger UI on the CS to verify).'

if (-not (Get-HVRestSession)) { return }

# Each entry: a logical group + the candidate paths to try. First non-empty
# response wins. Path probe fallback in HorizonRest.psm1 will auto-remap
# /v1/X to /X/v1, /v2/X, /external/v1/X etc., so we list the canonical
# /v1/config form here and let the runner swap.
$groups = @(
    @{ Group='Connection Servers';       Paths=@('/v1/monitor/connection-servers','/v1/config/connection-servers','/external/v1/connection-servers') }
    @{ Group='vCenter Registrations';    Paths=@('/v1/config/virtual-centers','/v1/monitor/virtual-centers') }
    @{ Group='Gateways (UAG/SG)';        Paths=@('/v1/monitor/gateways','/v1/config/gateways') }
    @{ Group='SAML Authenticators';      Paths=@('/v1/monitor/saml-authenticators','/v1/config/saml-authenticators') }
    @{ Group='RADIUS Authenticators';    Paths=@('/v1/monitor/radius-authenticators','/v1/config/radius-authenticators','/v1/config/radius') }
    @{ Group='True SSO';                 Paths=@('/v1/monitor/true-sso','/v1/config/true-sso') }
    @{ Group='Cert SSO Connectors';      Paths=@('/v1/config/certificate-sso-connectors','/v1/config/cert-sso') }
    @{ Group='Certificate Authorities';  Paths=@('/v1/config/certificate-authorities') }
    @{ Group='Permissions';              Paths=@('/v1/config/permissions') }
    @{ Group='Admin Roles';              Paths=@('/v1/config/admin-roles') }
    @{ Group='Administrators';           Paths=@('/v1/config/administrators') }
    @{ Group='Access Groups';            Paths=@('/v1/config/access-groups') }
    @{ Group='Network Ranges';           Paths=@('/v1/config/network-ranges') }
    @{ Group='Restricted Tags';          Paths=@('/v1/config/restricted-tags') }
    @{ Group='Help Desk Settings';       Paths=@('/v1/config/help-desk') }
    @{ Group='Event Database';           Paths=@('/v1/config/event-database') }
    @{ Group='Data Recovery Settings';   Paths=@('/v1/config/data-recovery-settings') }
    @{ Group='Workspace ONE Federation'; Paths=@('/v1/config/workspace-one') }
    @{ Group='Federation Certificates';  Paths=@('/v1/federation/certificates') }
    @{ Group='General Settings';         Paths=@('/v1/settings/general-settings') }
    @{ Group='License';                  Paths=@('/v1/settings/license') }
    @{ Group='Sites';                    Paths=@('/v1/sites') }
    @{ Group='Pods';                     Paths=@('/v1/pods') }
    @{ Group='Global Entitlements';      Paths=@('/v1/global-entitlements') }
    @{ Group='Global App Entitlements';  Paths=@('/v1/global-application-entitlements') }
    @{ Group='Persistent Disks';         Paths=@('/v1/persistent-disks') }
    @{ Group='Desktop Pools';            Paths=@('/v2/desktop-pools','/v1/desktop-pools') }
    @{ Group='Application Pools';        Paths=@('/v1/application-pools') }
    @{ Group='Farms';                    Paths=@('/v1/farms') }
    @{ Group='RDS Servers';              Paths=@('/v1/rds-servers') }
    @{ Group='Push Images';              Paths=@('/v1/monitor/push-images','/monitor/v1/push-images') }
    @{ Group='Desktop Pool Tasks';       Paths=@('/v1/monitor/desktop-pool-tasks') }
    @{ Group='Usage Statistics';         Paths=@('/v1/monitor/usage-statistics') }
)

foreach ($g in $groups) {
    $resp = $null
    $foundPath = ''
    foreach ($p in $g.Paths) {
        try {
            $r = Invoke-HVRest -Path $p -ErrorAction SilentlyContinue
            if ($r) {
                $arr = @($r)
                if ($arr.Count -gt 0) {
                    $resp = $arr
                    $foundPath = $p
                    break
                }
            }
        } catch { }
    }
    if (-not $resp) {
        [pscustomobject]@{
            Group       = $g.Group
            Items       = 0
            Source      = '(skipped - no endpoint returned data)'
            FieldSample = ''
            Notes       = 'Either this feature is not configured on the pod OR this Horizon build does not expose it via REST.'
        }
        continue
    }
    # Build a field-name sample from the first record
    $fields = @()
    $first = $resp[0]
    if ($first -and $first.PSObject -and $first.PSObject.Properties) {
        $fields = @($first.PSObject.Properties | Select-Object -First 12 | ForEach-Object { $_.Name })
    }
    [pscustomobject]@{
        Group       = $g.Group
        Items       = $resp.Count
        Source      = $foundPath
        FieldSample = ($fields -join ', ')
        Notes       = if ($resp.Count -eq 0) { 'endpoint reachable but empty' }
                      elseif (($fields | Measure-Object).Count -lt 4) { 'STUB-ONLY payload (<4 fields) - this Horizon build returns minimal data here' }
                      else { '' }
    }
}

$TableFormat = @{
    Items = { param($v,$row) if ([int]"$v" -gt 0) { 'ok' } else { 'warn' } }
    Notes = { param($v,$row) if ($v -match 'STUB|skipped') { 'warn' } else { '' } }
}
