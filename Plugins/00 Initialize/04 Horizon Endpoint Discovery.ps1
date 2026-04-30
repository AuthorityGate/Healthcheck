# Start of Settings
# End of Settings

$Title          = 'Horizon REST Endpoint Discovery'
$Header         = 'Per-endpoint probe of which Horizon REST paths return data on this pod'
$Comments       = @"
Single canonical-endpoint probe sweep run once per session and cached. Tells the operator at-a-glance which REST endpoints are reachable, which return rich data, and which are stubs / 404s on this Horizon build. Plugins downstream consult the same map (Get-HVEndpointMap) so they don't re-probe.

Status legend:
- ok          : endpoint returned objects with > 4 fields (rich data)
- empty       : endpoint returned 200 but 0 items
- stub        : endpoint returned objects but each has <= 4 fields (Horizon 8.6 /v1/monitor/connection-servers behavior)
- <httpcode>  : endpoint returned an HTTP error (404, 400, 500, etc.)
- unreachable : every variant path failed
"@
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '00 Initialize'
$Severity       = 'Info'
$Recommendation = "If 'connection-servers-config' is stub or the entitlements probe is 404 - the v0.94.0 multi-source pivot is engaged: SOAP + ADAM LDAPS reads pick up where REST falls short. Make sure VMware.Hv.Helper is installed (see Horizon tab badge) and the ADAM credential is set on the Horizon tab. If audit-events is 'unreachable' - the pod's syslog forwarding is the only path to event history."

if (-not (Get-HVRestSession)) { return }
if (-not (Get-Command -Name 'Get-HVEndpointMap' -ErrorAction SilentlyContinue)) {
    [pscustomobject]@{
        Endpoint   = '(plugin error)'
        Status     = ''
        Path       = ''
        Items      = ''
        FieldCount = ''
        Note       = 'Get-HVEndpointMap not exported by HorizonRest.psm1. v0.94.0 module update missing; redeploy.'
    }
    return
}

$map = Get-HVEndpointMap
if (-not $map -or $map.Count -eq 0) { return }

foreach ($name in $map.Keys) {
    $r = $map[$name]
    [pscustomobject]@{
        Endpoint   = $name
        Status     = $r.Status
        Path       = $r.Path
        Items      = $r.Count
        FieldCount = $r.FieldCount
        Note       = $r.Note
    }
}

$TableFormat = @{
    Status = { param($v,$row)
        if     ($v -eq 'ok')          { 'ok' }
        elseif ($v -eq 'empty')       { 'warn' }
        elseif ($v -eq 'stub')        { 'warn' }
        elseif ($v -eq 'unreachable') { 'bad' }
        elseif ([string]$v -match '^\d{3}$' -and [int]$v -ge 400) { 'bad' }
        else { '' }
    }
    FieldCount = { param($v,$row)
        if ([string]$v -eq '' -or [string]$v -eq '0') { '' }
        elseif ([int]"$v" -le 4) { 'warn' }
        else { 'ok' }
    }
}
