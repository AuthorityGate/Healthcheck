# Start of Settings
# End of Settings

$Title          = "Connection Server Inventory"
$Header         = "Found [count] Connection Server(s)"
$Comments       = "All Connection Servers known to this pod, with version and last-startup time."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = "10 Connection Servers"
$Severity       = "Info"

# Stub-mode short-circuit: when the pod's REST surface returns id+jwt-only
# on /v1/monitor/connection-servers (Horizon 8.6 behavior), this plugin
# can't get name/version/build/status from REST. Emit ONE info row pointing
# the operator at the WinRM Fallback plugin instead of N '(unknown)' rows.
if (Test-HVCSDataIsStub) {
    [pscustomobject]@{
        Name        = '(REST stub mode)'
        Version     = ''
        Build       = ''
        Status      = ''
        StartTime   = ''
        LastUpdated = ''
        Replication = ''
        Note        = "This pod's /v1/monitor/connection-servers returns id + jwt fields only - no name/version/build/status. See 'Connection Server Inventory (WinRM Fallback)' for real per-CS detail pulled directly from each host."
    }
    return
}

$cs = Get-HVConnectionServer
if (-not $cs) { return }

# Helper: try every plausible property name and return the first non-null /
# non-empty value. Different Horizon versions emit name/version/build under
# different keys; the Get-HVConnectionServer flatten promotes most of them
# but in some 2206+ shapes the canonical alias is not synthesized. Also
# filters PowerShell's '<missing-prop>'-as-string and the literal API
# value 'NONE'/'None' (Horizon emits "NONE" for empty replication state)
# so the report doesn't show the word 'None' in cells the operator reads
# as 'no data'.
function Get-FirstField {
    param($Obj, [string[]]$Names)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [string]) {
        if ($Names -contains 'name') { return $Obj }
        return $null
    }
    if (-not $Obj.PSObject) { return $null }
    foreach ($n in $Names) {
        if (-not $Obj.PSObject.Properties[$n]) { continue }
        $v = $Obj.PSObject.Properties[$n].Value
        if ($null -eq $v) { continue }
        $sv = "$v"
        if ([string]::IsNullOrWhiteSpace($sv)) { continue }
        if ($sv -ieq 'None' -or $sv -ieq 'null' -or $sv -ieq 'undefined') { continue }
        return $v
    }
    return $null
}

foreach ($c in $cs) {
    if ($null -eq $c) { continue }
    $name = Get-FirstField $c @('name','dns_name','host_name','hostname','server_name','cs_name','fqdn','id')
    $ver  = Get-FirstField $c @('version','cs_version','product_version','build_version','product_build_number')
    $bld  = Get-FirstField $c @('build','build_number','build_id')
    $stat = Get-FirstField $c @('status','health','state','operation_state')
    $startMs = Get-FirstField $c @('start_time','startup_time','last_startup','boot_time')
    $updMs   = Get-FirstField $c @('last_updated_timestamp','last_updated','timestamp','update_time','last_modified')
    $repl    = Get-FirstField $c @('replication','replication_status','replication_state')

    [pscustomobject]@{
        Name        = if ($name) { "$name" } else { '(unknown)' }
        Version     = if ($ver)  { "$ver" }  else { '' }
        Build       = if ($bld)  { "$bld" }  else { '' }
        Status      = if ($stat) { "$stat" } else { '' }
        StartTime   = if ($startMs) { try { (Get-Date '1970-01-01').AddMilliseconds([long]$startMs).ToLocalTime() } catch { '' } } else { '' }
        LastUpdated = if ($updMs)   { try { (Get-Date '1970-01-01').AddMilliseconds([long]$updMs).ToLocalTime()   } catch { '' } } else { '' }
        Replication = if ($repl) { "$repl" } else { '' }
    }
}
