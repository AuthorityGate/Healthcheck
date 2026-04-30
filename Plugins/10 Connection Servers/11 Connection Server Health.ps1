# Start of Settings
# End of Settings

$Title          = "Connection Servers - Unhealthy"
$Header         = "[count] Connection Server(s) report a non-OK status"
$Comments       = "Any CS whose REST monitor status is not 'OK' or whose replication is degraded is listed."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.2
$PluginCategory = "10 Connection Servers"
$Severity       = "P1"
$Recommendation = "Open Horizon Console -> Server Health, identify the failed service, restart 'VMware Horizon Connection Server' if safe, and verify event-DB / vCenter connectivity."

# Suppress entirely when the pod's REST surface is stub-only (Horizon 8.6
# /v1/monitor/connection-servers returns id+jwt). The WinRM Fallback plugin
# carries real status; this one would just emit '(unknown)' rows.
if (Test-HVCSDataIsStub) { return }

$cs = @(Get-HVConnectionServer)
if (-not $cs -or $cs.Count -eq 0) { return }

function Get-CSField { param($Obj,[string[]]$Names)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [string]) { if ($Names -contains 'name') { return $Obj }; return $null }
    if (-not $Obj.PSObject) { return $null }
    foreach ($n in $Names) {
        if (-not $Obj.PSObject.Properties[$n]) { continue }
        $v = $Obj.PSObject.Properties[$n].Value
        if ($null -ne $v -and "$v" -ne '') { return $v }
    }
    return $null
}

foreach ($c in $cs) {
    if ($null -eq $c) { continue }
    $name    = "$(Get-CSField $c @('name','dns_name','host_name','hostname','server_name','cs_name','fqdn','id'))"
    $status  = "$(Get-CSField $c @('status','health','state','operation_state'))"
    $repl    = "$(Get-CSField $c @('replication','replication_status','replication_state'))"
    if (-not $repl -and $c.PSObject -and $c.PSObject.Properties['replication']) {
        $rv = $c.replication
        if ($rv -and $rv.PSObject -and $rv.PSObject.Properties['status']) { $repl = "$($rv.status)" }
    }
    $version = "$(Get-CSField $c @('version','cs_version','product_version','build_version'))"
    $build   = "$(Get-CSField $c @('build','build_number','build_id','product_build_number'))"
    # Skip rows where the API didn't return assessable health data - some
    # Horizon 8.6 builds expose only id+jwt on /v1/monitor/connection-servers
    # and don't have a /config endpoint that returns status / version. Without
    # status, version, OR replication data, this plugin has nothing to assess
    # and emitting '(unknown)/(unknown)' rows is just false-positive noise.
    # The dedicated Connection Server Inventory (WinRM Fallback) plugin
    # produces real data via WinRM in this scenario.
    if (-not $status -and -not $version -and -not $repl) { continue }
    if (-not $status) { continue }
    $statusOk = ($status -eq 'OK')
    $repOk    = (-not $repl) -or ($repl -eq 'OK')
    if (-not ($statusOk -and $repOk)) {
        [pscustomobject]@{
            Name        = if ($name) { $name } else { '(unknown)' }
            Status      = $status
            Replication = if ($repl) { $repl } else { '(none)' }
            Version     = $version
            Build       = $build
        }
    }
}

$TableFormat = @{
    Status      = { param($v,$row) if ("$v" -ne 'OK') { 'bad' } else { '' } }
    Replication = { param($v,$row) if ("$v" -and "$v" -ne 'OK' -and "$v" -ne '(none)') { 'bad' } else { '' } }
}
