#Requires -Version 5.1
<#
    NutanixRest.psm1
    Thin REST wrapper for VMware Nutanix Prism Central + Prism Element.
    Targets v3 API at https://<pc>:9440/api/nutanix/v3 (default port 9440).
    Cmdlets emit objects with property names matching the v3 schema after
    ConvertTo-NTNXFlat lifts spec/status/resources up to the top level so
    plugins can dot-access common fields ($vm.name, $host.cpu_usage_pct).
#>

# Single-session and multi-session state, mirroring HorizonRest.psm1:
#   - $Script:NTNXSession  is the "active" session every plugin reads via
#     Get-NTNXRestSession / Invoke-NTNXRest.
#   - $Script:NTNXSessions is the keyed-by-FQDN map of every connected
#     Prism target. The runner calls Set-NTNXActiveSession to point the
#     "active" reference at one target before each per-target plugin call.
$Script:NTNXSession  = $null
$Script:NTNXSessions = @{}
$Script:NTNXPathProbe = New-Object System.Collections.ArrayList

function Get-NTNXPathProbe { ,$Script:NTNXPathProbe.ToArray() }

function Connect-NTNXRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][pscredential]$Credential,
        [int]$Port = 9440,
        [switch]$SkipCertificateCheck
    )

    # PowerShell 5.1 must be told to negotiate TLS 1.2 explicitly. Newer
    # Prism builds reject TLS 1.0/1.1 outright; without this the connect
    # fails before the request leaves the runner machine.
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -lt 6) {
        # Same trust-all dance as HorizonRest.psm1 + AppVolumesRest.psm1.
        Add-Type -TypeDefinition @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class NTNXTrustAll : ICertificatePolicy {
                public bool CheckValidationResult(ServicePoint sp, X509Certificate cert,
                                                   WebRequest req, int problem) { return true; }
            }
"@ -ErrorAction SilentlyContinue
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object NTNXTrustAll
    }

    $base = "https://${Server}:${Port}/api/nutanix/v3"
    $authHeader = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"))
    $headers = @{
        Authorization = $authHeader
        Accept        = 'application/json'
    }

    # Smoke test + role discovery via /users/me. Captures who the auth user
    # is and what permissions/roles they hold so plugins can short-circuit
    # endpoints they cannot access.
    $args = @{
        Uri         = "$base/users/me"
        Method      = 'Get'
        Headers     = $headers
        ContentType = 'application/json'
        ErrorAction = 'Stop'
        TimeoutSec  = 30
    }
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $args['SkipCertificateCheck'] = $true
    }
    $me = Invoke-RestMethod @args

    $Script:NTNXSession = [pscustomobject]@{
        Server               = $Server
        Port                 = $Port
        BaseUrl              = $base
        Credential           = $Credential
        Headers              = $headers
        SkipCertificateCheck = [bool]$SkipCertificateCheck
        ConnectedAt          = Get-Date
        # Captured calling-user metadata - used by plugins to gracefully
        # skip endpoints the role doesn't permit.
        CallingUser          = $me
        Permissions          = if ($me.status -and $me.status.resources -and $me.status.resources.access_control_policy_reference_list) { @($me.status.resources.access_control_policy_reference_list.name) } else { @() }
    }
    Write-Verbose "Connected to Nutanix Prism at ${Server}:$Port"
    $Script:NTNXSession
}

function Add-NTNXRestSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][pscredential]$Credential,
        [int]$Port = 9440,
        [switch]$SkipCertificateCheck
    )
    $sess = Connect-NTNXRest -Server $Server -Credential $Credential -Port $Port -SkipCertificateCheck:$SkipCertificateCheck
    if ($sess) { $Script:NTNXSessions["${Server}:${Port}"] = $sess }
    $sess
}

function Set-NTNXActiveSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Server)
    $key = $Server
    # Allow callers to pass either "fqdn:port" or just "fqdn"; resolve to
    # the first matching session if the port is omitted.
    if (-not $Script:NTNXSessions.ContainsKey($key)) {
        $match = $Script:NTNXSessions.Keys | Where-Object { $_ -like "$Server*" } | Select-Object -First 1
        if ($match) { $key = $match }
    }
    if ($Script:NTNXSessions.ContainsKey($key)) {
        $Script:NTNXSession = $Script:NTNXSessions[$key]
        return $Script:NTNXSession
    }
    return $null
}

function Get-NTNXAllSessions { $Script:NTNXSessions }

function Disconnect-NTNXRest {
    # v3 API has no logout endpoint - basic auth is per-call. We just clear
    # the in-memory session pointer so subsequent plugin calls return null.
    $Script:NTNXSession = $null
}

function Disconnect-NTNXAllSessions {
    if (-not $Script:NTNXSessions -or $Script:NTNXSessions.Count -eq 0) { return }
    $Script:NTNXSessions = @{}
    $Script:NTNXSession  = $null
}

function Get-NTNXRestSession { $Script:NTNXSession }

# Response-shape normaliser. Every v3 list response wraps its rows in:
#   { metadata, spec: { name, resources:{...} }, status: { name, state, resources:{...} } }
# Plugins read flat properties. ConvertTo-NTNXFlat walks each entity once
# and promotes properties from spec / status / metadata / *.resources to
# the top level (without overwriting anything already at the top).
function ConvertTo-NTNXFlat {
    param($Items)
    if ($null -eq $Items) { return $null }
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        if (-not ($item -is [pscustomobject] -or $item -is [psobject])) {
            $item; continue
        }
        $existing = @{}
        foreach ($p in $item.PSObject.Properties) { $existing[$p.Name] = $true }

        # Walk the canonical v3 sub-objects in priority order - status wins
        # over spec when both expose the same key (so power_state, state,
        # cluster reference reflect runtime not desired state).
        $walkOrder = @('status','spec','metadata')
        foreach ($container in $walkOrder) {
            $sub = $item.PSObject.Properties[$container]
            if (-not $sub -or -not $sub.Value) { continue }
            $val = $sub.Value
            if (-not ($val -is [pscustomobject] -or $val -is [psobject])) { continue }
            foreach ($p in $val.PSObject.Properties) {
                if (-not $existing.ContainsKey($p.Name)) {
                    Add-Member -InputObject $item -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
                    $existing[$p.Name] = $true
                }
            }
            # Walk one level deeper into .resources - that's where most
            # AHV data actually lives (power_state, host_reference,
            # num_vcpus_per_socket, memory_size_mib, etc.).
            $resProp = $val.PSObject.Properties['resources']
            if ($resProp -and $resProp.Value -and ($resProp.Value -is [pscustomobject] -or $resProp.Value -is [psobject])) {
                foreach ($r in $resProp.Value.PSObject.Properties) {
                    if (-not $existing.ContainsKey($r.Name)) {
                        Add-Member -InputObject $item -NotePropertyName $r.Name -NotePropertyValue $r.Value -Force
                        $existing[$r.Name] = $true
                    }
                }
            }
        }

        # Convenience derived fields from common Nutanix metric names.
        # CPU/memory utilization comes back as "ppm" (parts-per-million);
        # we surface a percentage so plugins don't all repeat /10000.
        if ($existing.ContainsKey('hypervisor_cpu_usage_ppm') -and -not $existing.ContainsKey('cpu_usage_pct')) {
            $ppm = [double]$item.hypervisor_cpu_usage_ppm
            Add-Member -InputObject $item -NotePropertyName cpu_usage_pct -NotePropertyValue ([math]::Round($ppm / 10000, 1)) -Force
        }
        if ($existing.ContainsKey('hypervisor_memory_usage_ppm') -and -not $existing.ContainsKey('memory_usage_pct')) {
            $ppm = [double]$item.hypervisor_memory_usage_ppm
            Add-Member -InputObject $item -NotePropertyName memory_usage_pct -NotePropertyValue ([math]::Round($ppm / 10000, 1)) -Force
        }
        $item
    }
}

function Invoke-NTNXRest {
<#
    .SYNOPSIS
    Thin Invoke-RestMethod wrapper for Nutanix v3. Adds Basic-auth header,
    handles paging via length+offset, and surfaces 401/403/404 in the
    same probe table other modules use for diagnostics.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Get','Post','Put','Delete')][string]$Method = 'Get',
        $Body,
        [int]$PageSize = 250,
        [switch]$NoPaging
    )
    if (-not $Script:NTNXSession) { return $null }

    $uri = "$($Script:NTNXSession.BaseUrl)$Path"
    $args = @{
        Uri         = $uri
        Method      = $Method
        Headers     = $Script:NTNXSession.Headers
        ContentType = 'application/json'
        ErrorAction = 'Stop'
        TimeoutSec  = 60
    }
    if ($Script:NTNXSession.SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $args['SkipCertificateCheck'] = $true
    }

    # v3 list endpoints use POST with a paging body. Detect: path ends in
    # /list and method is Get -> auto-flip to POST and supply a body.
    # Nutanix v3 expects 'kind' as the SINGULAR entity name (cluster, host,
    # vm, audit) - not the plural that appears in the URL path. Map the
    # most common ones explicitly; fall back to stripping a trailing 's'.
    $isList = $Path -match '/list$'
    if ($isList -and $Method -eq 'Get') {
        $pathPlural = ($Path.Trim('/') -split '/')[-2]
        $kindMap = @{
            'clusters'              = 'cluster'
            'hosts'                 = 'host'
            'vms'                   = 'vm'
            'storage_containers'    = 'storage_container'
            'subnets'               = 'subnet'
            'images'                = 'image'
            'vm_snapshots'          = 'vm_snapshot'
            'tasks'                 = 'task'
            'alerts'                = 'alert'
            'audits'                = 'audit'
            'categories'            = 'category'
            'protection_rules'      = 'protection_rule'
            'recovery_plans'        = 'recovery_plan'
            'availability_zones'    = 'availability_zone'
            'identity_providers'    = 'identity_provider'
            'users'                 = 'user'
            'roles'                 = 'role'
            'projects'              = 'project'
            'blueprints'            = 'blueprint'
            'files_servers'         = 'file_server'
            'network_security_rules'= 'network_security_rule'
            'access_control_policies' = 'access_control_policy'
            'volume_groups'         = 'volume_group'
            'vpcs'                  = 'vpc'
            'floating_ips'          = 'floating_ip'
            'vpn_connections'       = 'vpn_connection'
            'idps'                  = 'idp'
            'security_policies'     = 'security_policy'
        }
        $kind = if ($kindMap.ContainsKey($pathPlural)) { $kindMap[$pathPlural] }
                elseif ($pathPlural -match 's$') { $pathPlural -replace 's$','' }
                else { $pathPlural }
        $args['Method'] = 'Post'
        $args['Body']   = (@{ kind = $kind; length = $PageSize; offset = 0 } | ConvertTo-Json -Compress)
    } elseif ($Body) {
        $args['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }

    try {
        $resp = Invoke-RestMethod @args
        [void]$Script:NTNXPathProbe.Add([pscustomobject]@{ Path=$Path; Status=200; Result='OK' })
    } catch {
        $code = $null
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        if (-not $code) { try { $code = [int]$_.Exception.StatusCode } catch { } }
        if (-not $code -and $_.Exception.Message -match '\b(\d{3})\b') {
            $candidate = [int]$Matches[1]
            if ($candidate -ge 400 -and $candidate -lt 600) { $code = $candidate }
        }
        [void]$Script:NTNXPathProbe.Add([pscustomobject]@{ Path=$Path; Status=$code; Result=$_.Exception.Message })
        if ($code -in @(401,403,404,405,422,501)) { return $null }
        throw
    }

    if ($NoPaging -or $Method -ne 'Post' -or -not $isList) {
        if ($resp.entities) { return ,@(ConvertTo-NTNXFlat $resp.entities) }
        return (ConvertTo-NTNXFlat $resp)
    }

    # Paged list: keep walking offset until we've collected total_matches.
    # Reuse the same kind we computed above (already in the body).
    $all = New-Object System.Collections.ArrayList
    if ($resp.entities) { $null = $all.AddRange(@($resp.entities)) }
    $total = if ($resp.metadata -and $resp.metadata.total_matches) { [int]$resp.metadata.total_matches } else { $all.Count }
    $offset = $PageSize
    while ($all.Count -lt $total -and $offset -lt $total) {
        $args['Body'] = (@{ kind = $kind; length = $PageSize; offset = $offset } | ConvertTo-Json -Compress)
        try { $page = Invoke-RestMethod @args } catch { break }
        if (-not $page.entities -or @($page.entities).Count -eq 0) { break }
        $null = $all.AddRange(@($page.entities))
        $offset += $PageSize
    }
    ,@(ConvertTo-NTNXFlat $all.ToArray())
}

# --- v3 list wrappers (parallel to Get-HV* / Get-AV*) -----------------------
function Get-NTNXCluster              { Invoke-NTNXRest -Path '/clusters/list' }
function Get-NTNXHost                 { Invoke-NTNXRest -Path '/hosts/list' }
function Get-NTNXVM                   { Invoke-NTNXRest -Path '/vms/list' }
function Get-NTNXStorageContainer     { Invoke-NTNXRest -Path '/storage_containers/list' }
function Get-NTNXSubnet               { Invoke-NTNXRest -Path '/subnets/list' }
function Get-NTNXImage                { Invoke-NTNXRest -Path '/images/list' }
function Get-NTNXSnapshot             { Invoke-NTNXRest -Path '/vm_snapshots/list' }
function Get-NTNXTask                 { Invoke-NTNXRest -Path '/tasks/list' }
function Get-NTNXAlert                { Invoke-NTNXRest -Path '/alerts/list' }
function Get-NTNXAudit                { Invoke-NTNXRest -Path '/audits/list' }
function Get-NTNXCategory             { Invoke-NTNXRest -Path '/categories/list' }
function Get-NTNXProtectionRule       { Invoke-NTNXRest -Path '/protection_rules/list' }
function Get-NTNXRecoveryPlan         { Invoke-NTNXRest -Path '/recovery_plans/list' }
function Get-NTNXAvailabilityZone     { Invoke-NTNXRest -Path '/availability_zones/list' }
function Get-NTNXIdentityProvider     { Invoke-NTNXRest -Path '/identity_providers/list' }
function Get-NTNXUser                 { Invoke-NTNXRest -Path '/users/list' }
function Get-NTNXRole                 { Invoke-NTNXRest -Path '/roles/list' }
function Get-NTNXProject              { Invoke-NTNXRest -Path '/projects/list' }
function Get-NTNXBlueprint            { Invoke-NTNXRest -Path '/blueprints/list' }
function Get-NTNXFilesServer          { Invoke-NTNXRest -Path '/files_servers/list' }
function Get-NTNXNetworkSecurityRule  { Invoke-NTNXRest -Path '/network_security_rules/list' }
function Get-NTNXAccessControlPolicy  { Invoke-NTNXRest -Path '/access_control_policies/list' }
function Get-NTNXVolumeGroup          { Invoke-NTNXRest -Path '/volume_groups/list' }
function Get-NTNXVPC                  { Invoke-NTNXRest -Path '/vpcs/list' }
function Get-NTNXFloatingIp           { Invoke-NTNXRest -Path '/floating_ips/list' }
function Get-NTNXVPNConnection        { Invoke-NTNXRest -Path '/vpn_connections/list' }
function Get-NTNXIdpConfiguration     { Invoke-NTNXRest -Path '/idps/list' }
function Get-NTNXSamlIdp              { Invoke-NTNXRest -Path '/saml/idps/list' }
function Get-NTNXLicense              { Invoke-NTNXRest -Path '/licensing/cluster_licenses/list' }
function Get-NTNXLcmEntity            { Invoke-NTNXRest -Path '/lcm/v1.r0.b1/resources/entities/list' }
function Get-NTNXSecurityPolicy       { Invoke-NTNXRest -Path '/security_policies/list' }

# Per-entity detail (not paged - direct GET on uuid)
function Get-NTNXClusterDetail        { param([Parameter(Mandatory)][string]$Uuid) Invoke-NTNXRest -Path "/clusters/$Uuid" -NoPaging }
function Get-NTNXHostDetail           { param([Parameter(Mandatory)][string]$Uuid) Invoke-NTNXRest -Path "/hosts/$Uuid" -NoPaging }
function Get-NTNXVMDetail             { param([Parameter(Mandatory)][string]$Uuid) Invoke-NTNXRest -Path "/vms/$Uuid" -NoPaging }
function Get-NTNXStorageContainerDetail { param([Parameter(Mandatory)][string]$Uuid) Invoke-NTNXRest -Path "/storage_containers/$Uuid" -NoPaging }
function Get-NTNXSubnetDetail         { param([Parameter(Mandatory)][string]$Uuid) Invoke-NTNXRest -Path "/subnets/$Uuid" -NoPaging }

# Performance / stats. Nutanix exposes per-entity stats at v1 endpoints
# with a query-string filter. start_time_in_usecs / end_time_in_usecs are
# microseconds since epoch; interval_in_secs = 1800 (30 min) matches the
# rollup retention of ~30 days that ESXi's 30-min rollup uses.
function Get-NTNXVMStat {
    param(
        [Parameter(Mandatory)][string]$Uuid,
        [Parameter(Mandatory)][string]$Metric,
        [int]$LookbackDays = 30,
        [int]$IntervalSecs = 1800
    )
    $end = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 1000
    $start = ([DateTimeOffset]::UtcNow.AddDays(-$LookbackDays).ToUnixTimeMilliseconds()) * 1000
    Invoke-NTNXRest -Path ("/vms/$Uuid/stats?metrics={0}&start_time_in_usecs={1}&end_time_in_usecs={2}&interval_in_secs={3}" -f $Metric,$start,$end,$IntervalSecs) -NoPaging
}
function Get-NTNXHostStat {
    param(
        [Parameter(Mandatory)][string]$Uuid,
        [Parameter(Mandatory)][string]$Metric,
        [int]$LookbackDays = 30,
        [int]$IntervalSecs = 1800
    )
    $end = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 1000
    $start = ([DateTimeOffset]::UtcNow.AddDays(-$LookbackDays).ToUnixTimeMilliseconds()) * 1000
    Invoke-NTNXRest -Path ("/hosts/$Uuid/stats?metrics={0}&start_time_in_usecs={1}&end_time_in_usecs={2}&interval_in_secs={3}" -f $Metric,$start,$end,$IntervalSecs) -NoPaging
}
function Get-NTNXClusterStat {
    param(
        [Parameter(Mandatory)][string]$Uuid,
        [Parameter(Mandatory)][string]$Metric,
        [int]$LookbackDays = 30,
        [int]$IntervalSecs = 1800
    )
    $end = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 1000
    $start = ([DateTimeOffset]::UtcNow.AddDays(-$LookbackDays).ToUnixTimeMilliseconds()) * 1000
    Invoke-NTNXRest -Path ("/clusters/$Uuid/stats?metrics={0}&start_time_in_usecs={1}&end_time_in_usecs={2}&interval_in_secs={3}" -f $Metric,$start,$end,$IntervalSecs) -NoPaging
}
function Get-NTNXStorageStat {
    param(
        [Parameter(Mandatory)][string]$Uuid,
        [Parameter(Mandatory)][string]$Metric,
        [int]$LookbackDays = 30,
        [int]$IntervalSecs = 1800
    )
    $end = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 1000
    $start = ([DateTimeOffset]::UtcNow.AddDays(-$LookbackDays).ToUnixTimeMilliseconds()) * 1000
    Invoke-NTNXRest -Path ("/storage_containers/$Uuid/stats?metrics={0}&start_time_in_usecs={1}&end_time_in_usecs={2}&interval_in_secs={3}" -f $Metric,$start,$end,$IntervalSecs) -NoPaging
}

# Convenience: get the API version of the connected Prism, used by the
# diagnostic plugin to surface AOS / PC version in the report header.
function Get-NTNXVersion {
    Invoke-NTNXRest -Path '/cluster' -NoPaging
}

# Wildcard export covers every Get-NTNX*, Connect/Disconnect/Add/Set helpers,
# and ConvertTo-NTNXFlat - keeps the manifest from going stale as we add
# more wrappers.
Export-ModuleMember -Function Connect-NTNXRest, Disconnect-NTNXRest, Disconnect-NTNXAllSessions, `
    Add-NTNXRestSession, Set-NTNXActiveSession, Get-NTNXAllSessions, Get-NTNXRestSession, `
    Invoke-NTNXRest, ConvertTo-NTNXFlat, Get-NTNXPathProbe, `
    Get-NTNX*
