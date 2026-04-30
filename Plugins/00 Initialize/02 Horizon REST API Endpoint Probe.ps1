# Start of Settings
# End of Settings

$Title          = "Horizon REST API Endpoint Probe"
$Header         = "Per-endpoint REST API reachability + payload richness"
$Comments       = @"
Each row shows a Horizon REST endpoint that one or more plugins called, the URL we tried, the HTTP status, the field count of the first record returned, and the disposition. The Fields column is the key signal: a 200 with very few fields is a stub-only payload (Horizon 8.6 in particular returns just {id, jwt_info, jwt_support} on /v1/monitor/connection-servers - the actual metadata lives at /v1/config/connection-servers and the collector now merges both). Use this to triage why downstream plugins emit zero rows or 404 errors. Common causes:
- Connection Server REST API not exposed (firewall, /rest/swagger-ui returns 404)
- Service-account role missing 'Administrators' or 'Inventory Administrators'
- Horizon version older than 2106 (no REST surface for that endpoint)
- Pre-2206 Horizon that uses /v1/monitor/X form vs 2206+ /monitor/v1/X form
- Horizon 8.6 split: monitor endpoint returns JWT-only stub; config endpoint has names/versions
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = "00 Initialize"
$Severity       = "Info"
$Recommendation = @"
If everything shows 404 across the board: confirm the REST API is enabled on this Connection Server (https://<cs>/rest/swagger-ui.html should load) and that the service account holds at least 'Administrators (Read only)' role under Horizon Console -> Settings -> Administrators. If a path returns 200 but Fields is < 5 and flagged 'stub-only payload', that endpoint is Horizon-version-specific and the collector should be paired with its sibling /config/* (or /v2/*) endpoint - check that the merge logic in Get-HVConnectionServer / Get-HVDesktopPool has the matching pair recorded. If only some endpoints fail, the plugin row is logged with the exact path it tried -- compare that to the Swagger UI on this CS to see whether the path moved (Horizon REST has shifted between 2106 / 2206 / 2303 / 8.6 builds).
"@

if (-not (Get-HVRestSession)) {
    [pscustomobject]@{
        OriginalPath = '(no Horizon session)'
        TriedPath    = ''
        Status       = ''
        Fields       = ''
        SampleKeys   = ''
        Result       = 'Horizon REST not connected; skip.'
    }
    return
}

# Static probe set covering both monitor and config sides of paired
# resources. v0.93.51+ merges these pairs internally for Connection
# Servers; the probe surfaces the raw endpoints so the operator can see
# WHICH side answered with full data and WHICH side returned a stub.
$probeTargets = @(
    # Connection Servers (8.6 monitor returns stub; config has metadata)
    '/v1/monitor/connection-servers'
    '/v1/config/connection-servers'
    # vCenters - same monitor/config split applies
    '/v1/monitor/virtual-centers'
    '/v1/config/virtual-centers'
    # Gateways (UAGs)
    '/v1/monitor/gateways'
    '/v1/config/gateways'
    # Pods + Sites - small payloads, fewer 8.6 changes
    '/v1/pods'
    '/v1/sites'
    # Desktop Pools - v2 inventory, v1 config sides
    '/v2/desktop-pools'
    '/v1/desktop-pools'
    # Farms + Application Pools
    '/v1/farms'
    '/v1/application-pools'
    # Live state
    '/v1/machines'
    '/v1/rds-servers'
    '/v1/sessions'
    # Global entitlements + general settings + license
    '/v1/global-entitlements'
    '/v1/settings/general-settings'
    '/v1/settings/license'
)
foreach ($t in $probeTargets) {
    try { $null = Invoke-HVRest -Path $t -NoPaging:$($t -match '/settings/') -ErrorAction SilentlyContinue } catch { }
}

# Dynamic per-pool entitlement probe. v0.93.51 fixed pool entitlements by
# probing five endpoint variants per pool; surface the first variant's
# health here so the operator can confirm which one Horizon 8.6 honors.
try {
    $firstPool = (Get-HVDesktopPool | Select-Object -First 1)
    if ($firstPool -and $firstPool.id) {
        $entVariants = @(
            "/v2/desktop-pools/$($firstPool.id)/users"
            "/v2/desktop-pools/$($firstPool.id)/entitlements"
            "/v1/entitlements?desktop_pool_id=$($firstPool.id)"
            "/v1/entitlements/desktop-pools?id=$($firstPool.id)"
            "/v1/desktop-pools/$($firstPool.id)/entitlements"
        )
        foreach ($p in $entVariants) {
            try { $null = Invoke-HVRest -Path $p -NoPaging -ErrorAction SilentlyContinue } catch { }
        }
    }
} catch { }

$probe = Get-HVPathProbe
if (-not $probe -or $probe.Count -eq 0) {
    [pscustomobject]@{
        OriginalPath = '(no calls captured)'
        TriedPath    = ''
        Status       = ''
        Fields       = ''
        SampleKeys   = ''
        Result       = 'No REST calls have been made yet on this session.'
    }
    return
}

# Collapse to one row per OriginalPath - prefer the row that succeeded
# AND has the richest payload; otherwise the first row recorded.
$grouped = $probe | Group-Object OriginalPath
foreach ($g in $grouped) {
    $hits = @($g.Group | Where-Object { $_.Status -eq 200 })
    $hit = $null
    if ($hits.Count -gt 0) {
        # Pick the response with the most fields (avoids the stub-only
        # response winning over a richer alternate that also returned 200).
        $hit = $hits | Sort-Object @{
            Expression = { if ($null -eq $_.Fields -or "$($_.Fields)" -eq '') { 0 } else { [int]$_.Fields } }
            Descending = $true
        } | Select-Object -First 1
    } else {
        $hit = $g.Group | Select-Object -First 1
    }
    [pscustomobject]@{
        OriginalPath = $g.Name
        TriedPath    = $hit.TriedPath
        Status       = $hit.Status
        Fields       = if ($hit.PSObject.Properties['Fields']) { $hit.Fields } else { '' }
        SampleKeys   = if ($hit.PSObject.Properties['SampleKeys']) { $hit.SampleKeys } else { '' }
        Result       = $hit.Result
    }
}

$TableFormat = @{
    Status = { param($v,$row)
        if ([string]$v -eq '200') {
            # Mark stub-only 200s as warn so they don't read as fully healthy
            if ($row.Result -match 'stub-only') { 'warn' } else { 'ok' }
        }
        elseif ([string]$v -eq '404') { 'bad' }
        elseif ([string]$v -eq '403') { 'bad' }
        elseif ([string]$v -in @('401','405','501')) { 'warn' }
        else { '' }
    }
    Fields = { param($v,$row)
        # Empty fields cell on a 200 = no data items (zero rows, not stub)
        if ([string]$v -eq '' -or $null -eq $v) { '' }
        elseif ([int]$v -lt 5 -and $row.Status -eq 200) { 'warn' }
        elseif ([int]$v -ge 10) { 'ok' }
        else { '' }
    }
    Result = { param($v,$row)
        if ($v -match 'stub-only') { 'warn' }
        elseif ($v -match '^OK') { 'ok' }
        elseif ($v -match 'Forbidden|Error') { 'bad' }
        else { '' }
    }
}
