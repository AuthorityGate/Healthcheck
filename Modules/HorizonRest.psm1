#Requires -Version 5.1
<#
    HorizonRest.psm1
    Thin REST wrapper for VMware/Omnissa Horizon Connection Server.
    Targets Horizon 8 / Horizon 2x (REST API documented at:
        https://<cs>/rest/swagger-ui.html
    ).
    All cmdlets emit objects with property names matching the REST schema so
    plugins can dot into them directly.
#>

# Single-session and multi-session state coexist:
#   - $Script:HVSession  is the "active" session that every existing
#     plugin reads via Get-HVRestSession / Invoke-HVRest. Backward compat
#     stays intact.
#   - $Script:HVSessions  is a hashtable keyed by Server FQDN holding
#     EVERY connected pod. The runner iterates this dict for multi-pod
#     scans and calls Set-HVActiveSession to point the "active" reference
#     at a specific pod before invoking each plugin.
$Script:HVSession  = $null
$Script:HVSessions = @{}

# --- Diagnostics ---
# $Script:HVPathRemap caches successful path rewrites (original -> working).
# $Script:HVPathProbe records every path attempted with status code + chosen
# alternate, so the API Endpoint Probe plugin can surface "what worked / what
# didn't" to the operator. Cleared on Connect.
$Script:HVPathRemap = @{}
$Script:HVPathProbe = New-Object System.Collections.ArrayList

# Per-session probe state - keyed by Server FQDN.
#   .EndpointMap     hashtable of canonical-endpoint -> @{ Status; Path; FieldCount }
#                    populated by Invoke-HVEndpointDiscovery on first connect.
#   .AuditFilterShape  string ('A','B','C','none') chosen at first audit-events
#                    call so Get-HVAuditEvent doesn't burn 4 requests per call.
#   .CSDataIsStub    bool: did /v1/monitor/connection-servers come back as
#                    id+jwt-only (Horizon 8.6 behavior)? Plugins read this via
#                    Test-HVCSDataIsStub to suppress false-positive rows.
$Script:HVProbeState = @{}

function Get-HVPathProbe { ,$Script:HVPathProbe.ToArray() }

# Bool: did the connected pod return CS data in stub-only shape (id + jwt
# fields only, no name/version/build/status)? Plugins read this to decide
# whether to short-circuit instead of emitting '(unknown)' rows the operator
# already saw on the WinRM Fallback plugin. Lazy: probes on first call,
# caches result for the rest of the session.
function Test-HVCSDataIsStub {
    param([string]$Server)
    $key = if ($Server) { $Server } elseif ($Script:HVSession -and $Script:HVSession.Server) { $Script:HVSession.Server } else { '_default_' }
    if (-not $Script:HVProbeState.ContainsKey($key)) {
        $Script:HVProbeState[$key] = @{
            CSDataIsStub      = $null
            EndpointMap       = $null
            AuditFilterShape  = $null
        }
    }
    $st = $Script:HVProbeState[$key]
    if ($null -ne $st.CSDataIsStub) { return [bool]$st.CSDataIsStub }
    try {
        $monitor = @(Invoke-HVRest -Path '/v1/monitor/connection-servers' -ErrorAction SilentlyContinue)
        if (-not $monitor -or $monitor.Count -eq 0) {
            $st.CSDataIsStub = $true   # treat as stub when the endpoint returns nothing usable
            return $true
        }
        $first = $monitor[0]
        $names = @($first.PSObject.Properties.Name)
        # Stub indicators: 1) <= 4 properties; 2) ALL property names match
        # /^id$|jwt/  (Horizon 8.6 returns: id, jwt_info, jwt_support).
        $isStub = $false
        if ($names.Count -le 4) { $isStub = $true }
        if (-not $isStub) {
            $nonJwt = @($names | Where-Object { $_ -ne 'id' -and $_ -notmatch '(?i)jwt' })
            if ($nonJwt.Count -eq 0) { $isStub = $true }
        }
        # Strong indicator: no name/host_name/dns_name AND no version
        if (-not $isStub) {
            $hasName = $names -contains 'name' -or $names -contains 'host_name' -or $names -contains 'dns_name' -or $names -contains 'fqdn' -or $names -contains 'hostname'
            $hasVer  = $names -contains 'version' -or $names -contains 'cs_version' -or $names -contains 'product_version' -or $names -contains 'build_version'
            if (-not $hasName -and -not $hasVer) { $isStub = $true }
        }
        $st.CSDataIsStub = [bool]$isStub
        return $st.CSDataIsStub
    } catch {
        $st.CSDataIsStub = $false
        return $false
    }
}

# Returns/builds a hashtable of canonical-endpoint -> probe result. Each
# value is @{ Status='ok'|'stub'|'404'|'error'; Path=actually-attempted-path;
# FieldCount=int; Note=string }. Lazy: only probes on first call per session.
# Plugins use the Probe Diagnosis row to surface what's reachable on this pod.
function Get-HVEndpointMap {
    param([string]$Server, [switch]$Force)
    $key = if ($Server) { $Server } elseif ($Script:HVSession -and $Script:HVSession.Server) { $Script:HVSession.Server } else { '_default_' }
    if (-not $Script:HVProbeState.ContainsKey($key)) {
        $Script:HVProbeState[$key] = @{ CSDataIsStub=$null; EndpointMap=$null; AuditFilterShape=$null }
    }
    $st = $Script:HVProbeState[$key]
    if ($st.EndpointMap -and -not $Force) { return $st.EndpointMap }

    # Canonical endpoint name -> ordered list of paths to try. Same shape as
    # the chain inside the wrappers, kept in one place so the diagnostic row
    # shows the full picture without re-running each plugin's probe.
    $probes = [ordered]@{
        'connection-servers-monitor' = @('/v1/monitor/connection-servers')
        'connection-servers-config'  = @('/v1/config/connection-servers','/v2/config/connection-servers','/external/v1/connection-servers')
        'pods'                       = @('/v1/pods')
        'sites'                      = @('/v1/sites')
        'virtual-centers'            = @('/v1/monitor/virtual-centers')
        'desktop-pools'              = @('/v2/desktop-pools','/v1/desktop-pools')
        'farms'                      = @('/v1/farms')
        'machines'                   = @('/v1/machines')
        'sessions'                   = @('/v1/sessions')
        'gateways'                   = @('/v1/monitor/gateways')
        'enrollment-servers'         = @('/v1/monitor/enrollment-servers')
        'audit-events'               = @('/external/v1/audit-events')
        'entitlements'               = @('/v1/entitlements','/v2/entitlements','/external/v1/entitlements','/inventory/v1/entitlements')
        'global-entitlements'        = @('/v1/global-entitlements')
    }
    $map = [ordered]@{}
    foreach ($name in $probes.Keys) {
        $hit = $null
        foreach ($p in $probes[$name]) {
            try {
                $resp = @(Invoke-HVRest -Path $p -ErrorAction SilentlyContinue)
                if ($null -eq $resp) { continue }
                $count = $resp.Count
                $first = if ($count -gt 0) { $resp[0] } else { $null }
                $fc = 0
                if ($first -and $first.PSObject -and $first.PSObject.Properties) { $fc = @($first.PSObject.Properties).Count }
                $status = 'ok'
                $note   = ''
                if ($count -eq 0) { $status = 'empty'; $note = 'endpoint reachable but returned 0 items' }
                elseif ($fc -le 4) { $status = 'stub'; $note = "endpoint returned $count item(s) with only $fc field(s)" }
                $hit = @{ Status=$status; Path=$p; Count=$count; FieldCount=$fc; Note=$note }
                break
            } catch {
                $msg = $_.Exception.Message
                $statusCode = Get-HVErrorStatusCode $_
                $status = if ($statusCode) { "$statusCode" } else { 'error' }
                $hit = @{ Status=$status; Path=$p; Count=0; FieldCount=0; Note=$msg }
                # Keep walking - a 404 on the first path may yield ok on the next.
            }
        }
        if (-not $hit) { $hit = @{ Status='unreachable'; Path=($probes[$name][0]); Count=0; FieldCount=0; Note='no path returned' } }
        $map[$name] = $hit
    }
    $st.EndpointMap = $map
    return $map
}

# ---------- Response shape normalization ----------
# Horizon REST shape varies across versions:
#   - Pre-2206 monitor endpoints returned flat objects: { name, version, build,
#     status, replication, ... }
#   - 2206+ many alternates wrap status under .details: { id, status,
#     details: { name, version, build, replication, service_objects, ... } }
# Plugins read $c.name and similar flat properties. To keep them working
# regardless of which path served the data, after every successful call we
# walk each item and promote .details.* up to the top level (without
# overwriting existing properties).
function ConvertTo-HVFlat {
    # Horizon REST shape varies wildly by version + endpoint:
    #   - Pre-2206 monitor endpoints: flat top-level objects
    #   - 2206 monitor: { id, status, details:{ name, version, build } }
    #   - 2206 inventory: { id, name, version, settings:{...}, network_label_assignment_specs:{...} }
    #   - desktop pools: { id, type, source, general:{ display_name, ... }, provisioning_settings:{...} }
    #   - sessions: { id, user_id, machine_id, session_protocol, ... }
    # Plugins read flat properties like $c.name. To make every shape work
    # without rewriting plugins, we walk EVERY nested pscustomobject child
    # one level deep and promote each property to the top level (without
    # overwriting any property already present at the top).
    param($Items)
    if ($null -eq $Items) { return $null }

    # Sub-objects we explicitly walk; everything else nested can also be
    # promoted but we cap the lift to avoid surfacing plumbing fields like
    # `_links` from HATEOAS responses.
    $skipKeys = @('_links','links','metadata','metadata_url','events_database')

    # Canonical-alias map. The KEY is the canonical property plugins expect
    # to read; the VALUE is the ordered list of source property names we'll
    # check on the flattened object. If the canonical property is missing
    # but any of its aliases exist, copy the alias's value to the canonical
    # name. Plugins keep reading the canonical names and just work.
    $aliasMap = @{
        name         = @('name','display_name','dns_name','host_name','hostname','server_name','cs_name','machine_name','user_name','farm_name','pool_name','vc_name','base_image_name','snapshot_name','identity_name','fqdn')
        version      = @('version','cs_version','product_version','build_version','agent_version','horizon_agent_version')
        build        = @('build','build_number','build_id')
        status       = @('status','health','state','operation_state','running_state','session_state','machine_state','agent_state')
        machine_state = @('machine_state','state','agent_state','operation_state','running_state','status','power_state')
        agent_state  = @('agent_state','state','status','operation_state','machine_state')
        power_state  = @('power_state','state','running_state','status')
        last_updated_timestamp = @('last_updated_timestamp','last_updated','timestamp','update_time','last_modified')
        start_time   = @('start_time','startup_time','last_startup','boot_time')
        replication  = @('replication','replication_status','replication_state')
        agent_version = @('agent_version','horizon_agent_version','machine_agent_version')
        farm_name    = @('farm_name','farm_display_name','farm_id')
        farm_id      = @('farm_id')
        pool_name    = @('pool_name','desktop_pool_name','pool_display_name','pool_id')
        pool_id      = @('pool_id','desktop_pool_id')
        machine_name = @('machine_name','machine_display_name','machine_id')
        user_name    = @('user_name','username','user_display_name','sam_account_name','user_principal_name')
        session_protocol = @('session_protocol','protocol','display_protocol')
        session_count = @('session_count','num_sessions','session_count_estimate','load')
        max_sessions_count = @('max_sessions_count','max_sessions','session_limit','max_sessions_per_host')
    }

    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        if ($item -is [pscustomobject] -or $item -is [psobject]) {
            # Snapshot the top-level property list once - we mutate as we go.
            $existingProps = @{}
            foreach ($p in $item.PSObject.Properties) { $existingProps[$p.Name] = $true }

            # Semantic prefixes: when a sub-object is named like user_data /
            # machine_data / etc., we promote each child property TWICE -
            # once with the prefix (user_name, machine_name) and once
            # unprefixed if no top-level field of that name yet exists.
            # This is what makes session/event records work, where the
            # actual user name lives at user_data.name in 2206.
            $semanticPrefixes = @{
                'user_data'           = 'user'
                'machine_data'        = 'machine'
                'agent_data'          = 'agent'
                'client_data'         = 'client'
                'broker_session_data' = 'session'
                'session_data'        = 'session'
                'identity_data'       = 'identity'
                'farm_data'           = 'farm'
                'pool_data'           = 'pool'
                'desktop_pool_data'   = 'pool'
                'application_data'    = 'application'
                'authenticator_data'  = 'authenticator'
            }

            foreach ($p in @($item.PSObject.Properties)) {
                if ($skipKeys -contains $p.Name) { continue }
                $val = $p.Value
                # Walk only into pscustomobject / psobject sub-objects, not
                # arrays (an array's "properties" are length etc.) or scalars.
                if ($val -is [pscustomobject] -or $val -is [psobject]) {
                    if ($val -is [System.Array] -or $val -is [string] -or $val -is [int] -or $val -is [long] -or $val -is [bool] -or $val -is [datetime] -or $val -is [double]) { continue }

                    $prefix = if ($semanticPrefixes.ContainsKey($p.Name)) { $semanticPrefixes[$p.Name] } else { $null }

                    foreach ($sub in $val.PSObject.Properties) {
                        # Always create the unprefixed top-level alias when
                        # there's no conflict.
                        if (-not $existingProps.ContainsKey($sub.Name)) {
                            Add-Member -InputObject $item -NotePropertyName $sub.Name -NotePropertyValue $sub.Value -Force
                            $existingProps[$sub.Name] = $true
                        }
                        # Also create a prefixed alias (e.g. user_name) so
                        # the field can be addressed unambiguously even when
                        # multiple sub-objects expose a property with the
                        # same name.
                        if ($prefix) {
                            $prefixedName = "${prefix}_$($sub.Name)"
                            if (-not $existingProps.ContainsKey($prefixedName)) {
                                Add-Member -InputObject $item -NotePropertyName $prefixedName -NotePropertyValue $sub.Value -Force
                                $existingProps[$prefixedName] = $true
                            }
                        }
                    }
                }
            }

            # Canonical aliasing: for each canonical property the plugins
            # expect, if it's missing AND any alias exists with a non-null
            # value, copy that value into the canonical property.
            foreach ($canonical in $aliasMap.Keys) {
                $haveCanonical = $false
                if ($existingProps.ContainsKey($canonical)) {
                    $cv = $item.PSObject.Properties[$canonical].Value
                    if ($null -ne $cv -and "$cv" -ne '') { $haveCanonical = $true }
                }
                if ($haveCanonical) { continue }
                foreach ($alias in $aliasMap[$canonical]) {
                    if ($existingProps.ContainsKey($alias)) {
                        $av = $item.PSObject.Properties[$alias].Value
                        if ($null -ne $av -and "$av" -ne '') {
                            Add-Member -InputObject $item -NotePropertyName $canonical -NotePropertyValue $av -Force
                            $existingProps[$canonical] = $true
                            break
                        }
                    }
                }
            }
        }
        $item
    }
}

# Snapshot the property keys of an endpoint's first object - lets the schema
# diagnostic plugin show what shape Horizon actually returned without dumping
# customer data.
function Get-HVSchemaSnapshot {
    param($Items, [int]$MaxKeys = 60)
    $first = @($Items) | Where-Object { $_ } | Select-Object -First 1
    if (-not $first) { return $null }
    $props = @($first.PSObject.Properties.Name) | Select-Object -First $MaxKeys
    # Walk every nested pscustomobject one level so the schema dump shows
    # exactly which property names live where; this is what we use to
    # diagnose "table count > 0 but cells blank".
    $nested = @{}
    foreach ($p in $first.PSObject.Properties) {
        $val = $p.Value
        if ($val -is [pscustomobject] -or $val -is [psobject]) {
            if ($val -is [System.Array] -or $val -is [string] -or $val -is [int] -or $val -is [long] -or $val -is [bool] -or $val -is [datetime] -or $val -is [double]) { continue }
            $nested[$p.Name] = @($val.PSObject.Properties.Name) | Select-Object -First $MaxKeys
        }
    }
    [pscustomobject]@{
        TopLevelKeys = ($props -join ', ')
        NestedKeys   = ($nested.Keys | ForEach-Object { "$($_): $($nested[$_] -join ', ')" }) -join ' | '
    }
}

# Defensive status-code extractor. PowerShell 5.1 throws WebException;
# PowerShell 7 throws HttpResponseException. Different exception classes
# expose StatusCode through different property paths. As a last resort we
# regex the message (".*404.*Not Found"). Returns $null if nothing matches.
function Get-HVErrorStatusCode {
    param($ErrorRecord)
    $code = $null
    try {
        if ($ErrorRecord.Exception.Response -and $ErrorRecord.Exception.Response.StatusCode) {
            $code = [int]$ErrorRecord.Exception.Response.StatusCode
        }
    } catch { }
    if (-not $code) {
        try {
            if ($ErrorRecord.Exception.PSObject.Properties['StatusCode']) {
                $code = [int]$ErrorRecord.Exception.StatusCode
            }
        } catch { }
    }
    if (-not $code) {
        # Final fallback: parse the message ("...does not indicate success: 404 (Not Found).")
        $m = $null
        try { $m = [string]$ErrorRecord.Exception.Message } catch { }
        if ($m -and $m -match '\b(\d{3})\b') {
            $candidate = [int]$Matches[1]
            if ($candidate -ge 400 -and $candidate -lt 600) { $code = $candidate }
        }
    }
    $code
}

function Connect-HVRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][pscredential]$Credential,
        [string]$Domain,
        [switch]$SkipCertificateCheck
    )

    if (-not $Domain) {
        if ($Credential.UserName -match '\\') {
            $Domain    = $Credential.UserName.Split('\')[0]
            $UserName  = $Credential.UserName.Split('\')[1]
        } elseif ($Credential.UserName -match '@') {
            $UserName  = $Credential.UserName.Split('@')[0]
            $Domain    = $Credential.UserName.Split('@')[1]
        } else {
            throw "Domain not supplied and username '$($Credential.UserName)' has no domain qualifier."
        }
    } else {
        $UserName = $Credential.UserName -replace '^.*\\','' -replace '@.*$',''
    }

    $body = @{
        username = $UserName
        password = $Credential.GetNetworkCredential().Password
        domain   = $Domain
    } | ConvertTo-Json

    $base = "https://$Server/rest"
    $args = @{
        Uri         = "$base/login"
        Method      = 'Post'
        Body        = $body
        ContentType = 'application/json'
        ErrorAction = 'Stop'
    }
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $args['SkipCertificateCheck'] = $true
    } elseif ($SkipCertificateCheck) {
        Add-Type -TypeDefinition @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class HVTrustAll : ICertificatePolicy {
                public bool CheckValidationResult(ServicePoint sp, X509Certificate cert,
                                                   WebRequest req, int problem) { return true; }
            }
"@ -ErrorAction SilentlyContinue
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object HVTrustAll
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor `
            [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls
    }

    $resp = Invoke-RestMethod @args

    # Reset diagnostics for the new session
    $Script:HVPathRemap = @{}
    $Script:HVPathProbe = New-Object System.Collections.ArrayList
    if ($Script:HVProbeState.ContainsKey($Server)) { $Script:HVProbeState.Remove($Server) }

    $Script:HVSession = [pscustomobject]@{
        Server               = $Server
        BaseUrl              = $base
        AccessToken          = $resp.access_token
        RefreshToken         = $resp.refresh_token
        SkipCertificateCheck = [bool]$SkipCertificateCheck
        Headers              = @{
            Authorization = "Bearer $($resp.access_token)"
            Accept        = 'application/json'
        }
        ConnectedAt          = Get-Date
    }
    Write-Verbose "Connected to Horizon REST at $Server."
    $Script:HVSession
}

function Disconnect-HVRest {
    [CmdletBinding()]
    param()
    if (-not $Script:HVSession) { return }
    try {
        $body = @{ refresh_token = $Script:HVSession.RefreshToken } | ConvertTo-Json
        $args = @{
            Uri         = "$($Script:HVSession.BaseUrl)/logout"
            Method      = 'Post'
            Body        = $body
            ContentType = 'application/json'
            Headers     = $Script:HVSession.Headers
            ErrorAction = 'SilentlyContinue'
        }
        if ($Script:HVSession.SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
            $args['SkipCertificateCheck'] = $true
        }
        Invoke-RestMethod @args | Out-Null
    } catch { }
    $Script:HVSession = $null
}

function Get-HVRestSession { $Script:HVSession }

# Multi-pod support. Plugins read $Script:HVSession via Get-HVRestSession; the
# runner stores connections to ALL pods in $Script:HVSessions and points the
# "active" pointer at one pod at a time. Plugins are unchanged - they iterate
# whatever the active pod returns; the runner takes care of the loop.

function Add-HVRestSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][pscredential]$Credential,
        [string]$Domain,
        [switch]$SkipCertificateCheck
    )
    # Connect-HVRest sets $Script:HVSession; we capture and stash by FQDN.
    $sess = Connect-HVRest -Server $Server -Credential $Credential -Domain $Domain -SkipCertificateCheck:$SkipCertificateCheck
    if ($sess) { $Script:HVSessions[$Server] = $sess }
    $sess
}

function Set-HVActiveSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Server)
    if ($Script:HVSessions -and $Script:HVSessions.ContainsKey($Server)) {
        $Script:HVSession = $Script:HVSessions[$Server]
        # Reset path-remap cache - different pods may run different Horizon
        # builds, so a remap discovered on pod A is not valid on pod B.
        $Script:HVPathRemap = @{}
        $Script:HVPathProbe = New-Object System.Collections.ArrayList
        return $Script:HVSession
    }
    return $null
}

function Get-HVAllSessions { $Script:HVSessions }

function Disconnect-HVAllSessions {
    if (-not $Script:HVSessions -or $Script:HVSessions.Count -eq 0) { return }
    foreach ($key in @($Script:HVSessions.Keys)) {
        try {
            $Script:HVSession = $Script:HVSessions[$key]
            Disconnect-HVRest
        } catch { }
    }
    $Script:HVSessions = @{}
    $Script:HVSession = $null
}

function Invoke-HVRest {
<#
    .SYNOPSIS
    Thin Invoke-RestMethod wrapper that adds the bearer header, paginates, and
    auto-refreshes the access token if the server responds with 401.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Get','Post','Put','Delete','Patch')][string]$Method = 'Get',
        $Body,
        [int]$PageSize = 1000,
        [switch]$NoPaging
    )
    # Soft-fail: if no Horizon session, return $null so plugins can simply skip.
    # The runner starts cleanly with vCenter only, with Horizon only, or both.
    if (-not $Script:HVSession) { return $null }

    # If we previously discovered an alternate path for this endpoint (because
    # the original 404'd), skip the dance and use the cached remap.
    $originalPath = $Path
    if ($Script:HVPathRemap -and $Script:HVPathRemap.ContainsKey($Path)) {
        $Path = $Script:HVPathRemap[$Path]
    }

    $uri    = "$($Script:HVSession.BaseUrl)$Path"
    $hasQs  = $Path -match '\?'
    $offset = 0
    $all    = New-Object System.Collections.ArrayList

    do {
        $pagedUri = $uri
        if (-not $NoPaging -and $Method -eq 'Get') {
            $sep      = $(if ($hasQs) { '&' } else { '?' })
            $pagedUri = "{0}{1}page=1&size={2}&start={3}" -f $uri,$sep,$PageSize,$offset
        }
        $args = @{
            Uri         = $pagedUri
            Method      = $Method
            Headers     = $Script:HVSession.Headers
            ContentType = 'application/json'
            ErrorAction = 'Stop'
        }
        if ($Body) { $args['Body'] = ($Body | ConvertTo-Json -Depth 8) }
        if ($Script:HVSession.SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
            $args['SkipCertificateCheck'] = $true
        }
        try {
            $resp = Invoke-RestMethod @args
            # Only record one probe row per call (offset==0). Pagination
            # otherwise produces N rows of "OK" for the same OriginalPath.
            # Capture payload field count of the first record so a 200 with
            # a stub-only response (e.g. Horizon 8.6 /v1/monitor/connection-
            # servers returns just {id, jwt_info, jwt_support}) is visually
            # distinguishable from a 200 with full metadata.
            if ($offset -eq 0) {
                $fieldCount = 0
                $sampleKeys = ''
                $first = if ($resp -is [System.Array]) { @($resp)[0] } else { $resp }
                if ($first -and $first.PSObject -and $first.PSObject.Properties) {
                    $names = @($first.PSObject.Properties | ForEach-Object { $_.Name })
                    $fieldCount = $names.Count
                    if ($fieldCount -gt 0) {
                        $sampleKeys = ($names | Select-Object -First 6) -join ','
                    }
                }
                $stubFlag = ($fieldCount -gt 0 -and $fieldCount -lt 5)
                [void]$Script:HVPathProbe.Add([pscustomobject]@{
                    OriginalPath = $originalPath
                    TriedPath    = $Path
                    Status       = 200
                    Result       = if ($stubFlag) { "OK (stub-only payload: $fieldCount fields)" } else { 'OK' }
                    Fields       = $fieldCount
                    SampleKeys   = $sampleKeys
                })
            }
        } catch {
            $code = Get-HVErrorStatusCode -ErrorRecord $_
            if ($code -eq 401) {
                # Token expired - refresh once
                $refresh = @{ refresh_token = $Script:HVSession.RefreshToken } | ConvertTo-Json
                try {
                    $r = Invoke-RestMethod -Uri "$($Script:HVSession.BaseUrl)/refresh" -Method Post `
                            -Body $refresh -ContentType 'application/json' -ErrorAction Stop
                    $Script:HVSession.AccessToken      = $r.access_token
                    $Script:HVSession.Headers.Authorization = "Bearer $($r.access_token)"
                    $args['Headers'] = $Script:HVSession.Headers
                    $resp = Invoke-RestMethod @args
                } catch {
                    [void]$Script:HVPathProbe.Add([pscustomobject]@{
                        OriginalPath=$originalPath; TriedPath=$Path; Status=401; Result='RefreshFailed'
                    })
                    return $null
                }
            } elseif ($code -eq 404) {
                # Endpoint not at expected path. Horizon REST has shifted across
                # versions and not always consistently:
                #   - 8.0/2006: /rest/v1/monitor/X, /rest/v1/inventory/X
                #   - 2206:    moved many endpoints; common forms:
                #              /rest/monitor/v1/X (path order swap)
                #              /rest/inventory/v1/X
                #              /rest/config/v1/X
                #   - 2303+:   /rest/external/v1/X, /rest/v2/X for some
                # We exhaustively try every reasonable rewrite. First match wins
                # and is cached in $Script:HVPathRemap for the rest of the run.
                $alternates = @()
                $tail = $null
                if ($Path -match '^/v(\d)/(?:monitor|inventory|config|external|entitlements)/(.+)$') {
                    # /v1/monitor/X form -> swap or strip the modifier
                    $ver = $Matches[1]; $tail = $Matches[2]
                } elseif ($Path -match '^/(?:monitor|inventory|config|external|entitlements)/v(\d)/(.+)$') {
                    # /monitor/v1/X form -> swap or strip the modifier
                    $ver = $Matches[1]; $tail = $Matches[2]
                } elseif ($Path -match '^/v(\d)/(.+)$') {
                    # /v1/X bare form -> add a modifier
                    $ver = $Matches[1]; $tail = $Matches[2]
                }
                if ($tail) {
                    $vers = @($ver)
                    if ($ver -ne '1') { $vers += '1' }
                    if ($ver -ne '2') { $vers += '2' }
                    foreach ($v in $vers) {
                        # entitlements is a real Horizon 8.6 namespace - try it
                        # alongside the historical monitor/inventory/config/external
                        # set so a /v1/entitlements/X 404 falls through to the
                        # newer /v2/X or /entitlements/v1/X form automatically.
                        foreach ($mod in @('monitor','inventory','config','external','entitlements')) {
                            $alternates += "/v$v/$mod/$tail"
                            $alternates += "/$mod/v$v/$tail"
                        }
                        $alternates += "/v$v/$tail"
                    }
                    # de-dupe + skip already-tried path
                    $alternates = $alternates | Where-Object { $_ -ne $Path } | Select-Object -Unique
                }

                [void]$Script:HVPathProbe.Add([pscustomobject]@{
                    OriginalPath=$originalPath; TriedPath=$Path; Status=404; Result='Trying alternates'
                })

                $altResp = $null; $altPathFound = $null
                foreach ($altPath in $alternates) {
                    $altUri = if (-not $NoPaging -and $Method -eq 'Get') {
                        $altHasQs = $altPath -match '\?'
                        $altSep   = $(if ($altHasQs) { '&' } else { '?' })
                        "$($Script:HVSession.BaseUrl)$altPath$($altSep)page=1&size=$PageSize&start=$offset"
                    } else { "$($Script:HVSession.BaseUrl)$altPath" }
                    $altArgs = $args.Clone()
                    $altArgs['Uri'] = $altUri
                    try {
                        $altResp = Invoke-RestMethod @altArgs
                        $altPathFound = $altPath
                        $Script:HVPathRemap[$originalPath] = $altPath
                        [void]$Script:HVPathProbe.Add([pscustomobject]@{
                            OriginalPath=$originalPath; TriedPath=$altPath; Status=200; Result='OK (remapped)'
                        })
                        Write-Verbose "Horizon path remap: $originalPath -> $altPath"
                        break
                    } catch {
                        $ac = Get-HVErrorStatusCode -ErrorRecord $_
                        [void]$Script:HVPathProbe.Add([pscustomobject]@{
                            OriginalPath=$originalPath; TriedPath=$altPath; Status=$ac; Result='Skipped'
                        })
                        if ($ac -and $ac -ne 404 -and $ac -ne 405 -and $ac -ne 501) { break }
                    }
                }
                if ($null -ne $altResp) {
                    $resp = $altResp
                } else {
                    if (-not $Script:HVSession.Warned404) {
                        $Script:HVSession | Add-Member -NotePropertyName Warned404 -NotePropertyValue $true -Force
                        Write-Warning "Horizon REST endpoint $originalPath not available on $($Script:HVSession.Server) (and no known alternate path responded). Plugins depending on this endpoint will emit zero rows instead of erroring. See '00 Initialize > Horizon REST API Endpoint Probe' in the report for the full list of paths attempted."
                    }
                    return $null
                }
            } elseif ($code -eq 405 -or $code -eq 501) {
                [void]$Script:HVPathProbe.Add([pscustomobject]@{
                    OriginalPath=$originalPath; TriedPath=$Path; Status=$code; Result='Method/feature not supported'
                })
                return $null
            } elseif ($code -eq 403) {
                [void]$Script:HVPathProbe.Add([pscustomobject]@{
                    OriginalPath=$originalPath; TriedPath=$Path; Status=403; Result='Forbidden (insufficient role/permission for this endpoint)'
                })
                return $null
            } else {
                # Genuinely unexpected (5xx, network). Record + rethrow so the
                # plugin reports it as an error.
                [void]$Script:HVPathProbe.Add([pscustomobject]@{
                    OriginalPath=$originalPath; TriedPath=$Path; Status=$code; Result=("Error: " + $_.Exception.Message)
                })
                throw
            }
        }

        if ($NoPaging -or $Method -ne 'Get') { return (ConvertTo-HVFlat $resp) }

        if ($resp -is [System.Array]) {
            $null = $all.AddRange($resp)
            if ($resp.Count -lt $PageSize) { break }
            $offset += $PageSize
        } else {
            return (ConvertTo-HVFlat $resp)
        }
    } while ($true)

    ,@(ConvertTo-HVFlat $all.ToArray())
}

# ---------- Convenience wrappers (one per inventory endpoint) ------------------
# Endpoint paths drawn from the Horizon REST API reference. Where an older Horizon
# (pre-2306) lacks an endpoint, the wrapper returns $null and lets the plugin skip.

function Get-HVConnectionServer {
    # Horizon 8.6+ /v1/monitor/connection-servers returns ONLY id + jwt
    # data - all the rich metadata (name, version, build, status,
    # replication) lives at /v1/config/connection-servers OR is reachable
    # only via the per-id /v1/config/connection-servers/{id} detail call.
    # We pull the monitor list (live status), pull the config list (or per-id
    # config when the list endpoint isn't there), merge by id, and return
    # one composite object per CS. Plugins reading $c.name / $c.version /
    # $c.build now get real data instead of empty strings.
    $monitor = @(Invoke-HVRest -Path '/v1/monitor/connection-servers')
    if (-not $monitor -or $monitor.Count -eq 0) { return @() }

    # Try the LIST config endpoint first (newer Horizon). Includes /external/v1/
    # for builds where /v1/config redirects to a stub-only endpoint.
    # Richness check: if the response has <= 4 fields per item it's
    # the same stub shape as /v1/monitor (id + jwt_info + jwt_support);
    # keep trying alternates until we find one with name/version/etc.
    $configList = $null
    foreach ($p in @(
        '/v1/config/connection-servers',
        '/v2/config/connection-servers',
        '/config/v1/connection-servers',
        '/external/v1/connection-servers',
        '/v2/connection-servers'
    )) {
        try {
            $resp = @(Invoke-HVRest -Path $p -ErrorAction SilentlyContinue)
            if ($resp -and $resp.Count -gt 0) {
                $first = $resp[0]
                $fieldCount = if ($first.PSObject -and $first.PSObject.Properties) { @($first.PSObject.Properties).Count } else { 0 }
                if ($fieldCount -gt 4) {
                    $configList = $resp
                    break
                }
                # else stub-only, keep trying
            }
        } catch { }
    }

    # Build {id -> configRow} map. Fall back to per-id detail when no list
    # endpoint returned a rich enough payload.
    $cfgMap = @{}
    if ($configList) {
        foreach ($c in $configList) {
            if ($c -and $c.id) { $cfgMap[$c.id] = $c }
        }
    } else {
        foreach ($m in $monitor) {
            if (-not $m -or -not $m.id) { continue }
            $cfg = $null
            foreach ($detailPath in @(
                "/v1/config/connection-servers/$($m.id)",
                "/v2/config/connection-servers/$($m.id)",
                "/external/v1/connection-servers/$($m.id)"
            )) {
                try {
                    $cfg = Invoke-HVRest -Path $detailPath -NoPaging -ErrorAction SilentlyContinue
                    if ($cfg) {
                        $fc = if ($cfg.PSObject -and $cfg.PSObject.Properties) { @($cfg.PSObject.Properties).Count } else { 0 }
                        if ($fc -gt 4) { break } else { $cfg = $null }
                    }
                } catch { }
            }
            if ($cfg) { $cfgMap[$m.id] = $cfg }
        }
    }

    # Merge: every monitor row plus matching config row's properties (config
    # wins for name/version/build because monitor often doesn't carry them).
    # Last-resort fallback: when no /config endpoint surfaced rich data
    # (Horizon 8.6 here returns id+jwt-only on every variant), synthesize
    # a 'name' on the connected CS at least, using the FQDN the operator
    # typed in the Horizon tab. Plugins that read $c.name then have one
    # real hostname instead of all GUIDs. Peer CS metadata still isn't
    # available - that requires either a richer REST surface or the
    # WinRM-based 'Connection Server Inventory (WinRM Fallback)' plugin.
    $connectedFqdn = if ($Script:HVSession -and $Script:HVSession.Server) { $Script:HVSession.Server } else { $null }
    $needSynthName = (-not $cfgMap -or $cfgMap.Count -eq 0)
    if ($needSynthName -and $connectedFqdn -and $monitor.Count -gt 0) {
        # Apply the connected FQDN to the FIRST record only; we can't
        # safely guess peer FQDNs from REST alone.
        Add-Member -InputObject $monitor[0] -NotePropertyName 'name' -NotePropertyValue $connectedFqdn -Force
        Add-Member -InputObject $monitor[0] -NotePropertyName 'host_name' -NotePropertyValue $connectedFqdn -Force
        Add-Member -InputObject $monitor[0] -NotePropertyName 'fqdn' -NotePropertyValue $connectedFqdn -Force
    }

    foreach ($m in $monitor) {
        if (-not $m) { continue }
        $cfg = if ($m.id -and $cfgMap.ContainsKey($m.id)) { $cfgMap[$m.id] } else { $null }
        if ($cfg) {
            foreach ($prop in $cfg.PSObject.Properties) {
                if ($prop.Name -eq 'id') { continue }
                $existing = $m.PSObject.Properties[$prop.Name]
                if ($existing) {
                    # Prefer config value when monitor's is empty/null
                    if ($null -eq $existing.Value -or "$($existing.Value)" -eq '') {
                        Add-Member -InputObject $m -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                    }
                } else {
                    Add-Member -InputObject $m -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                }
            }
        }
        $m
    }
}
function Get-HVPod {
    # Horizon 8.6 returns empty objects on /v1/pods (no id, no name) so the
    # runner's per-CS pod-key dedup turned every replica into a "distinct
    # pod" and ran every plugin N times for an N-CS replica pair. Detect
    # the empty-pods stub and synthesize a single local pod entry from the
    # connected session's identity so callers get a usable pod-key.
    $raw = @(Invoke-HVRest -Path '/v1/pods')
    if (-not $raw -or $raw.Count -eq 0) { return @() }
    # 'Useful' = at least one of id / name is present and non-empty.
    $useful = @($raw | Where-Object {
        $_ -and (
            ($_.PSObject.Properties['id']   -and "$($_.id)"   -ne '') -or
            ($_.PSObject.Properties['name'] -and "$($_.name)" -ne '')
        )
    })
    if ($useful.Count -gt 0) { return $raw }
    # All entries are empty stubs - synthesize ONE local-pod row keyed off
    # the connected CS so the runner's dedup logic collapses every replica
    # CS down to one iteration. Mark _synthesized so the diagnostic plugin
    # can show the operator that we filled this in.
    $srv  = if ($Script:HVSession -and $Script:HVSession.Server) { $Script:HVSession.Server } else { 'local-pod' }
    $stub = [pscustomobject]@{
        id            = "synth-$srv"
        name          = $srv
        local_pod     = $true
        localPod      = $true
        _synthesized  = $true
        _stub_reason  = "/v1/pods returned $($raw.Count) empty object(s); pod identity unknown via REST"
    }
    return @($stub)
}
function Get-HVSite              { Invoke-HVRest -Path '/v1/sites' }
function Get-HVVirtualCenter     { Invoke-HVRest -Path '/v1/monitor/virtual-centers' }
function Get-HVDesktopPool       { Invoke-HVRest -Path '/v2/desktop-pools' }
function Get-HVFarm              { Invoke-HVRest -Path '/v1/farms' }
function Get-HVApplicationPool   { Invoke-HVRest -Path '/v1/application-pools' }
function Get-HVMachine           { Invoke-HVRest -Path '/v1/machines' }
function Get-HVRdsServer         { Invoke-HVRest -Path '/v1/rds-servers' }
function Get-HVSession           { Invoke-HVRest -Path '/v1/sessions' }
function Get-HVGlobalEntitlement { Invoke-HVRest -Path '/v1/global-entitlements' }
function Get-HVGlobalSettings    { Invoke-HVRest -Path '/v1/settings/general-settings' -NoPaging }
function Get-HVLicense           { Invoke-HVRest -Path '/v1/settings/license' -NoPaging }
function Get-HVGateway           { Invoke-HVRest -Path '/v1/monitor/gateways' }

# --- Expanded coverage (added v0.93.1 to surface the full Horizon REST surface) ---
# Each wrapper points at the canonical endpoint; the path remap fallback in
# Invoke-HVRest copes with version-specific path differences.

# Authentication / identity
function Get-HVRADIUSAuthenticator   { Invoke-HVRest -Path '/v1/config/radius-authenticators' }
function Get-HVSAMLAuthenticator     { Invoke-HVRest -Path '/v1/config/saml-authenticators' }
function Get-HVSAMLAuthenticatorV2   { Invoke-HVRest -Path '/v2/config/saml-authenticators' }
function Get-HVCertSSOConnector      { Invoke-HVRest -Path '/v1/config/certificate-sso-connectors' }
function Get-HVTrueSSO               { Invoke-HVRest -Path '/v1/config/true-sso' }
function Get-HVDomain                { Invoke-HVRest -Path '/v1/config/domains' }
function Get-HVAdminUser             { Invoke-HVRest -Path '/v1/config/administrators' }
function Get-HVAdminRole             { Invoke-HVRest -Path '/v1/config/admin-roles' }
function Get-HVAdminPermission       { Invoke-HVRest -Path '/v1/config/permissions' }
function Get-HVPrivilegeGroup        { Invoke-HVRest -Path '/v1/config/privilege-groups' }

# Network and access policy
function Get-HVNetworkRange          { Invoke-HVRest -Path '/v1/config/network-ranges' }
function Get-HVNetworkInterface      { Invoke-HVRest -Path '/v1/config/network-interfaces' }
function Get-HVAccessGroup           { Invoke-HVRest -Path '/v1/config/access-groups' }
function Get-HVRestrictedTag         { Invoke-HVRest -Path '/v1/config/restricted-tags' }

# Inventory: deeper detail
function Get-HVMachineDetail {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/machines/$Id" -NoPaging
}
function Get-HVDesktopPoolDetail {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v2/desktop-pools/$Id" -NoPaging
}
function Get-HVFarmDetail {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/farms/$Id" -NoPaging
}
function Get-HVPersistentDisk        { Invoke-HVRest -Path '/v1/persistent-disks' }
function Get-HVUserOrGroupSummary    { Invoke-HVRest -Path '/v1/users-or-groups' }
function Get-HVEntitlement {
    # Returns per-pool entitlement map: pool/farm/app-pool -> users/groups.
    Invoke-HVRest -Path '/v1/entitlements'
}
function Get-HVDesktopPoolEntitlement {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/desktop-pools/$Id/entitlements" -NoPaging
}
function Get-HVApplicationPoolEntitlement {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/application-pools/$Id/entitlements" -NoPaging
}
function Get-HVFarmEntitlement {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/farms/$Id/entitlements" -NoPaging
}

# Federation (Cloud Pod Architecture)
function Get-HVCPAGlobalAccessGroup    { Invoke-HVRest -Path '/v1/global-access-groups' }
function Get-HVCPAGlobalApplicationEnt { Invoke-HVRest -Path '/v1/global-application-entitlements' }
function Get-HVCPAFederation           { Invoke-HVRest -Path '/v1/federation' -NoPaging }
function Get-HVCPAHomeSiteAssignment   { Invoke-HVRest -Path '/v1/home-site-assignments' }

# Monitoring / live state
function Get-HVMonitorEventDB        { Invoke-HVRest -Path '/v1/monitor/event-database' -NoPaging }
function Get-HVMonitorRdsServer      { Invoke-HVRest -Path '/v1/monitor/rds-servers' }
function Get-HVMonitorFarm           { Invoke-HVRest -Path '/v1/monitor/farms' }
function Get-HVMonitorDesktopPool    { Invoke-HVRest -Path '/v1/monitor/desktop-pools' }
function Get-HVMonitorSAML           { Invoke-HVRest -Path '/v1/monitor/saml-authenticators' }
function Get-HVMonitorRADIUS         { Invoke-HVRest -Path '/v1/monitor/radius-authenticators' }
function Get-HVMonitorTrueSSO        { Invoke-HVRest -Path '/v1/monitor/true-sso' }
function Get-HVMonitorDomain         { Invoke-HVRest -Path '/v1/monitor/domains' }
function Get-HVMonitorEnrollmentSrv  { Invoke-HVRest -Path '/v1/monitor/enrollment-servers' }

# Helpdesk plug-in (only when enabled on the pod)
function Get-HVHelpdeskSession {
    param([string]$UserName, [string]$MachineName, [int]$Limit = 100)
    $qs = @()
    if ($UserName)    { $qs += "user_name=$([uri]::EscapeDataString($UserName))" }
    if ($MachineName) { $qs += "machine_name=$([uri]::EscapeDataString($MachineName))" }
    $q = if ($qs.Count) { '?' + ($qs -join '&') } else { '' }
    Invoke-HVRest -Path "/v1/helpdesk/sessions$q"
}
function Get-HVHelpdeskUser {
    param([Parameter(Mandatory)][string]$UserId)
    Invoke-HVRest -Path "/v1/helpdesk/users/$UserId" -NoPaging
}

# Settings (one per settings page)
function Get-HVSecuritySettings        { Invoke-HVRest -Path '/v1/settings/security-settings' -NoPaging }
function Get-HVDataRecoverySettings    { Invoke-HVRest -Path '/v1/settings/data-recovery-settings' -NoPaging }
function Get-HVProductLicensingUsage   { Invoke-HVRest -Path '/v1/settings/license/usage' -NoPaging }
function Get-HVStorageAcceleratorPolicy { Invoke-HVRest -Path '/v1/settings/storage-accelerator-policy' -NoPaging }
function Get-HVClientRestrictions      { Invoke-HVRest -Path '/v1/settings/client-restrictions' -NoPaging }
function Get-HVUnauthenticatedAccess   { Invoke-HVRest -Path '/v1/config/unauthenticated-access-users' }
function Get-HVProxyConfig             { Invoke-HVRest -Path '/v1/config/proxy' -NoPaging }
function Get-HVCertificate             { Invoke-HVRest -Path '/v1/config/certificates' }
function Get-HVTaskActivity            { Invoke-HVRest -Path '/v1/monitor/task-activity' }
function Get-HVUsageStatistics         { Invoke-HVRest -Path '/v1/monitor/usage-statistics' -NoPaging }

# Per-pool extras
function Get-HVDesktopPoolMachine {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/desktop-pools/$Id/machines"
}
function Get-HVDesktopPoolUsage {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/desktop-pools/$Id/usage" -NoPaging
}
function Get-HVDesktopPoolPushImage {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/desktop-pools/$Id/push-images"
}
function Get-HVFarmRdsServer {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/farms/$Id/rds-servers"
}

# Image catalog (vSphere VMs available as desktop pool source)
function Get-HVBaseImageVm           { Invoke-HVRest -Path '/v1/base-image-vms' }
function Get-HVBaseImageSnapshot {
    param([Parameter(Mandatory)][string]$VmId)
    Invoke-HVRest -Path "/v1/base-image-vms/$VmId/snapshots"
}
function Get-HVDatacenter            { Invoke-HVRest -Path '/v1/external/datacenters' }
function Get-HVCustomizationSpec     { Invoke-HVRest -Path '/v1/external/customization-specifications' }
function Get-HVDatastore             { Invoke-HVRest -Path '/v1/external/datastores' }
function Get-HVHostOrCluster         { Invoke-HVRest -Path '/v1/external/hosts-or-clusters' }
function Get-HVResourcePool          { Invoke-HVRest -Path '/v1/external/resource-pools' }
function Get-HVActiveDirectoryDomain { Invoke-HVRest -Path '/v1/external/ad-domains' }
function Get-HVADContainer           { Invoke-HVRest -Path '/v1/external/ad-containers' }

# --- Policies ---
function Get-HVGlobalPolicy          { Invoke-HVRest -Path '/v1/global-policies' -NoPaging }
function Get-HVGlobalPolicyV2        { Invoke-HVRest -Path '/v2/global-policies' -NoPaging }
function Get-HVDesktopPoolPolicy {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/desktop-pools/$Id/policies" -NoPaging
}
function Get-HVApplicationPoolPolicy {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/application-pools/$Id/policies" -NoPaging
}
function Get-HVUserPolicy {
    param([Parameter(Mandatory)][string]$UserId)
    Invoke-HVRest -Path "/v1/users-or-groups/$UserId/policies" -NoPaging
}

# --- Global Sessions / Federation members ---
function Get-HVGlobalSession         { Invoke-HVRest -Path '/v1/global-sessions' }
function Get-HVGlobalEntitlementMember {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/global-entitlements/$Id/members"
}
function Get-HVGlobalEntitlementMachine {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/global-entitlements/$Id/machines"
}
function Get-HVGlobalApplicationEntitlement      { Invoke-HVRest -Path '/v1/global-application-entitlements' }
function Get-HVGlobalApplicationEntitlementMember {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/global-application-entitlements/$Id/members"
}

# --- Messages / branding ---
function Get-HVDisclaimerMessage     { Invoke-HVRest -Path '/v1/config/disclaimer-message' -NoPaging }
function Get-HVLogonBanner           { Invoke-HVRest -Path '/v1/config/logon-banner' -NoPaging }
function Get-HVAvgLogonTime          { Invoke-HVRest -Path '/v1/monitor/usage-statistics/avg-logon-time' -NoPaging }
function Get-HVConnectivityMessage   { Invoke-HVRest -Path '/v1/config/connectivity-messages' -NoPaging }

# --- Event forwarding ---
function Get-HVEventDatabaseConfig   { Invoke-HVRest -Path '/v1/config/event-database' -NoPaging }
function Get-HVSyslogConfig          { Invoke-HVRest -Path '/v1/config/syslog' -NoPaging }
function Get-HVCEFSyslogConfig       { Invoke-HVRest -Path '/v1/config/cef-syslog' -NoPaging }
function Get-HVEventForwardingConfig { Invoke-HVRest -Path '/v1/config/event-forwarding' -NoPaging }

# --- Backup / data recovery ---
function Get-HVBackupConfig          { Invoke-HVRest -Path '/v1/config/backup' -NoPaging }
function Get-HVADAMReplication       { Invoke-HVRest -Path '/v1/monitor/adam-replication' -NoPaging }

# --- Additional monitor endpoints ---
function Get-HVMonitorAuthInstance          { Invoke-HVRest -Path '/v1/monitor/auth-instances' }
function Get-HVMonitorAuditEventSummary     { Invoke-HVRest -Path '/v1/monitor/audit-events-summary' -NoPaging }
function Get-HVMonitorEventSummary          { Invoke-HVRest -Path '/v1/monitor/event-summary' -NoPaging }
function Get-HVMonitorSessionSummary        { Invoke-HVRest -Path '/v1/monitor/sessions-summary' -NoPaging }
function Get-HVMonitorLoadBalancing         { Invoke-HVRest -Path '/v1/monitor/load-balancing-counts' -NoPaging }
function Get-HVMonitorReplicaServerPair     { Invoke-HVRest -Path '/v1/monitor/replica-server-pairs' }
function Get-HVMonitorSystemHealthCount     { Invoke-HVRest -Path '/v1/monitor/system-health-counts' -NoPaging }
function Get-HVMonitorVirtualCenter {
    # Distinct from Get-HVVirtualCenter (which already targets the same path);
    # exposed for callers that prefer the "monitor.*" naming.
    Invoke-HVRest -Path '/v1/monitor/virtual-centers'
}
function Get-HVMonitorComposer              { Invoke-HVRest -Path '/v1/monitor/view-composers' }

# --- Pool / machine ancillary ---
function Get-HVMachineMessage {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/machines/$Id/messages"
}
function Get-HVMachineRecoveryAction {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/machines/$Id/recovery-actions" -NoPaging
}
function Get-HVDesktopPoolHomeSite {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/desktop-pools/$Id/home-sites" -NoPaging
}
function Get-HVRdsServerSession {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/rds-servers/$Id/sessions"
}
function Get-HVRdsServerProcess {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/rds-servers/$Id/processes"
}
function Get-HVMachineSession {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/machines/$Id/sessions"
}

# --- Connection server-level config ---
function Get-HVConnectionServerSetting {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/config/connection-servers/$Id" -NoPaging
}
function Get-HVConnectionServerCertificate {
    param([Parameter(Mandatory)][string]$Id)
    Invoke-HVRest -Path "/v1/config/connection-servers/$Id/certificate" -NoPaging
}
function Get-HVCSPairingPassword     { Invoke-HVRest -Path '/v1/config/cs-pairing-passwords' }

# --- Image management / instant clone ---
function Get-HVInstantCloneDomainAccount { Invoke-HVRest -Path '/v1/config/ic-domain-accounts' }
function Get-HVInstantCloneEngineState   { Invoke-HVRest -Path '/v1/monitor/instant-clone-engine' -NoPaging }
function Get-HVImageManagementStream     { Invoke-HVRest -Path '/v1/external/image-management/streams' }
function Get-HVImageManagementMarker     { Invoke-HVRest -Path '/v1/external/image-management/markers' }

# --- Client restrictions & security ---
function Get-HVClientGroup           { Invoke-HVRest -Path '/v1/config/client-groups' }
function Get-HVTLSProfile            { Invoke-HVRest -Path '/v1/config/tls-profiles' }
function Get-HVCipherList            { Invoke-HVRest -Path '/v1/config/cipher-list' -NoPaging }
function Get-HVHTTPHeaderConfig      { Invoke-HVRest -Path '/v1/config/http-headers' -NoPaging }
function Get-HVURLContentRedirection { Invoke-HVRest -Path '/v1/config/url-content-redirection' }

# --- Smart card / certificate trust ---
function Get-HVSmartCardConfig       { Invoke-HVRest -Path '/v1/config/smart-card' -NoPaging }
function Get-HVSmartCardCATrust      { Invoke-HVRest -Path '/v1/config/smart-card-ca-trust' }
function Get-HVCertificateRevocationList { Invoke-HVRest -Path '/v1/config/crl' }

# --- Global pod policies / unentitled state ---
function Get-HVPodAssignment         { Invoke-HVRest -Path '/v1/global-pod-assignments' }
function Get-HVHomeSiteOverride      { Invoke-HVRest -Path '/v1/global-home-site-overrides' }
function Get-HVUnauthenticatedClient { Invoke-HVRest -Path '/v1/config/unauthenticated-clients' }

# --- ThinApp / UEM ---
function Get-HVThinAppApplication    { Invoke-HVRest -Path '/v1/thinapp-applications' }
function Get-HVThinAppPackageState   { Invoke-HVRest -Path '/v1/thinapp-package-states' }
function Get-HVUEMApplication        { Invoke-HVRest -Path '/v1/uem-applications' }
function Get-HVUEMBaseline           { Invoke-HVRest -Path '/v1/uem-baselines' }

# --- vSphere / external inventory (extras) ---
function Get-HVExternalNetworkLabel       { Invoke-HVRest -Path '/v1/external/network-labels' }
function Get-HVExternalContentLibrary     { Invoke-HVRest -Path '/v1/external/content-libraries' }
function Get-HVExternalContentLibraryItem { Invoke-HVRest -Path '/v1/external/content-library-items' }
function Get-HVExternalStoragePolicy      { Invoke-HVRest -Path '/v1/external/storage-policies' }
function Get-HVExternalVMotionConfig      { Invoke-HVRest -Path '/v1/external/cluster-vmotion-config' }
function Get-HVExternalVCenterPermission  { Invoke-HVRest -Path '/v1/external/vcenter-permissions' }
function Get-HVExternalVMTemplate         { Invoke-HVRest -Path '/v1/external/vm-templates' }

# --- Recovery / pairing ---
function Get-HVPodPairingPassword         { Invoke-HVRest -Path '/v1/config/pod-pairing-passwords' }
function Get-HVRecoveryPasswordState      { Invoke-HVRest -Path '/v1/monitor/recovery-passwords' -NoPaging }

# --- Notifications, feature toggles, telemetry ---
function Get-HVNotification               { Invoke-HVRest -Path '/v1/notifications' }
function Get-HVFeatureState               { Invoke-HVRest -Path '/v1/feature-states' }
function Get-HVTelemetryConfig            { Invoke-HVRest -Path '/v1/config/telemetry' -NoPaging }
function Get-HVDataCollector              { Invoke-HVRest -Path '/v1/monitor/data-collectors' }

# --- Bulk / paginated machine snapshots ---
function Get-HVMachineSnapshotInventory   { Invoke-HVRest -Path '/v1/external/snapshots' }
function Get-HVOrphanedMachine            { Invoke-HVRest -Path '/v1/monitor/orphaned-machines' }
function Get-HVProblemMachine             { Invoke-HVRest -Path '/v1/monitor/problem-machines' }
function Get-HVMissingMachine             { Invoke-HVRest -Path '/v1/monitor/missing-machines' }

# --- Audit events with custom filter ---
function Get-HVAuditEventByModule {
    param([Parameter(Mandatory)][string]$Module, [int]$SinceHours = 24)
    $since = ([DateTimeOffset](Get-Date).AddHours(-$SinceHours)).ToUnixTimeMilliseconds()
    $filter = @{
        type = 'And'
        filters = @(
            @{ type='GreaterThan'; name='time';   value=$since }
            @{ type='Equals';      name='module'; value=$Module }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    $enc = [System.Web.HttpUtility]::UrlEncode($filter)
    Invoke-HVRest -Path "/external/v1/audit-events?filter=$enc"
}

# --- Generic helper: dump everything for a single object id ---
function Get-HVObjectGraph {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('desktop-pool','farm','machine','application-pool','rds-server')] [string]$Type,
          [Parameter(Mandatory)][string]$Id)
    switch ($Type) {
        'desktop-pool' {
            [pscustomobject]@{
                Detail        = (Get-HVDesktopPoolDetail -Id $Id)
                Machines      = (Get-HVDesktopPoolMachine -Id $Id)
                Entitlements  = (Get-HVDesktopPoolEntitlement -Id $Id)
                Usage         = (Get-HVDesktopPoolUsage -Id $Id)
                Policies      = (Get-HVDesktopPoolPolicy -Id $Id)
                PushImages    = (Get-HVDesktopPoolPushImage -Id $Id)
                HomeSites     = (Get-HVDesktopPoolHomeSite -Id $Id)
            }
        }
        'farm' {
            [pscustomobject]@{
                Detail        = (Get-HVFarmDetail -Id $Id)
                RdsServers    = (Get-HVFarmRdsServer -Id $Id)
                Entitlements  = (Get-HVFarmEntitlement -Id $Id)
            }
        }
        'machine' {
            [pscustomobject]@{
                Detail   = (Get-HVMachineDetail -Id $Id)
                Sessions = (Get-HVMachineSession -Id $Id)
                Messages = (Get-HVMachineMessage -Id $Id)
                Recovery = (Get-HVMachineRecoveryAction -Id $Id)
            }
        }
        'application-pool' {
            [pscustomobject]@{
                Entitlements = (Get-HVApplicationPoolEntitlement -Id $Id)
                Policies     = (Get-HVApplicationPoolPolicy -Id $Id)
            }
        }
        'rds-server' {
            [pscustomobject]@{
                Sessions  = (Get-HVRdsServerSession -Id $Id)
                Processes = (Get-HVRdsServerProcess -Id $Id)
            }
        }
    }
}

function Get-HVAuditEvent {
    [CmdletBinding()]
    param([int]$SinceHours = 24, [string[]]$Severities = @('AUDIT_FAIL','ERROR','WARNING'))
    $since = ([DateTimeOffset](Get-Date).AddHours(-$SinceHours)).ToUnixTimeMilliseconds()

    # /external/v1/audit-events filter syntax. Different Horizon builds accept
    # different filter shapes. Probe the four shapes ONCE per session, cache
    # which one the server accepted, and reuse it for the rest of the run.
    # Without the cache every plugin that touches audit events ate four
    # 400-Bad-Request round-trips before falling through.
    $key = if ($Script:HVSession -and $Script:HVSession.Server) { $Script:HVSession.Server } else { '_default_' }
    if (-not $Script:HVProbeState.ContainsKey($key)) {
        $Script:HVProbeState[$key] = @{ CSDataIsStub=$null; EndpointMap=$null; AuditFilterShape=$null }
    }
    $st = $Script:HVProbeState[$key]

    $shapes = [ordered]@{
        'A' = @{
            type    = 'And'
            filters = @(
                @{ type='GreaterThan'; name='time'; value=$since }
                @{ type='In';          name='severity'; value=$Severities }
            )
        }
        'B' = @{
            type    = 'And'
            filters = @(
                @{ type='GreaterThan'; field='time'; value=$since }
                @{ type='In';          field='severity'; value=$Severities }
            )
        }
        'C' = @{
            type    = 'GreaterThan'
            name    = 'time'
            value   = $since
        }
    }
    $tryOrder = if ($st.AuditFilterShape -and $shapes.Contains($st.AuditFilterShape)) {
        @($st.AuditFilterShape) + @($shapes.Keys | Where-Object { $_ -ne $st.AuditFilterShape })
    } else { @($shapes.Keys) }

    foreach ($shape in $tryOrder) {
        $f = $shapes[$shape]
        try {
            $json = $f | ConvertTo-Json -Depth 6 -Compress
            $enc = [System.Web.HttpUtility]::UrlEncode($json)
            $resp = Invoke-HVRest -Path "/external/v1/audit-events?filter=$enc" -ErrorAction Stop
            if ($null -ne $resp) {
                $st.AuditFilterShape = $shape
                if ($shape -eq 'C' -and $Severities) {
                    $resp = @($resp | Where-Object { $_.severity -in $Severities })
                }
                return $resp
            }
        } catch { }
    }

    # Last resort: no filter at all - cache 'none' so we don't keep retrying
    # the parameterized shapes from every plugin call.
    try {
        $resp = @(Invoke-HVRest -Path '/external/v1/audit-events' -ErrorAction SilentlyContinue)
        if ($null -ne $resp) {
            $st.AuditFilterShape = 'none'
            $resp = @($resp | Where-Object {
                ($null -eq $_.time -or [long]$_.time -ge $since) -and
                (-not $Severities -or $_.severity -in $Severities)
            })
            return $resp
        }
    } catch { }
    return @()
}

# Helper: resolve a Horizon ID reference (id property) to its display name via a
# named lookup table the plugin builds. Plugins use this to flatten foreign keys.
function Resolve-HVId {
    param($Id, $Map)
    if (-not $Id) { return $null }
    if ($Map.ContainsKey($Id)) { return $Map[$Id] }
    return $Id
}

# Export every public helper - the wildcard pulls in the full Get-HV* surface
# (now ~150 wrappers) plus Connect/Disconnect/Invoke/Resolve helpers without
# needing to maintain a manual list.
Export-ModuleMember -Function Connect-HVRest, Disconnect-HVRest, Disconnect-HVAllSessions, `
    Add-HVRestSession, Set-HVActiveSession, `
    Get-HVRestSession, Invoke-HVRest, `
    Resolve-HVId, ConvertTo-HVFlat, Get-HVSchemaSnapshot, Get-HVPathProbe, Get-HVErrorStatusCode, `
    Test-HVCSDataIsStub, Get-HVEndpointMap, `
    Get-HV*
