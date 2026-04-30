# Start of Settings
# End of Settings

$Title          = "vCenter Service Status"
$Header         = "vCenter VAMI service health snapshot"
$Comments       = "Pulls Get-View on the ServiceInstance to enumerate the vCenter Server's service inventory: vmware-vpostgres, vmware-vapi-endpoint, vsphere-ui, content-library, etc. Stopped or degraded services explain why the UI suddenly stops accepting logins or content-library replication stalls."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "Restart non-running services from VAMI (https://<vc>:5480) -> Services. Confirm root cause via /var/log/<service>/. Recurring failures point at backing-store or memory pressure."

if (-not $Global:VCConnected) { return }

# Service availability is exposed differently on different vCenter builds.
# The ServiceInstance content has a SessionManager + ServiceContent. The
# AuthorizationManager + LicenseManager need to respond fast - we ping each
# via Get-View and time the response.

$tests = @(
    @{ Name = 'SessionManager';      Lookup = { Get-View -Id (Get-View ServiceInstance).Content.SessionManager -ErrorAction Stop } }
    @{ Name = 'AuthorizationManager';Lookup = { Get-View -Id (Get-View ServiceInstance).Content.AuthorizationManager -ErrorAction Stop } }
    @{ Name = 'LicenseManager';      Lookup = { Get-View -Id (Get-View ServiceInstance).Content.LicenseManager -ErrorAction Stop } }
    @{ Name = 'PerfManager';         Lookup = { Get-View -Id (Get-View ServiceInstance).Content.PerfManager -ErrorAction Stop } }
    @{ Name = 'ViewManager';         Lookup = { Get-View -Id (Get-View ServiceInstance).Content.ViewManager -ErrorAction Stop } }
    @{ Name = 'EventManager';        Lookup = { Get-View -Id (Get-View ServiceInstance).Content.EventManager -ErrorAction Stop } }
    @{ Name = 'TaskManager';         Lookup = { Get-View -Id (Get-View ServiceInstance).Content.TaskManager -ErrorAction Stop } }
    @{ Name = 'AlarmManager';        Lookup = { Get-View -Id (Get-View ServiceInstance).Content.AlarmManager -ErrorAction Stop } }
    @{ Name = 'ExtensionManager';    Lookup = { Get-View -Id (Get-View ServiceInstance).Content.ExtensionManager -ErrorAction Stop } }
)
foreach ($t in $tests) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $err = $null
    try { & $t.Lookup | Out-Null } catch { $err = $_.Exception.Message }
    $sw.Stop()
    [pscustomobject]@{
        Service  = $t.Name
        Latency  = $sw.ElapsedMilliseconds
        Status   = if ($err) { 'ERROR' } else { 'OK' }
        Note     = $err
    }
}

$TableFormat = @{
    Status = { param($v,$row) if ($v -eq 'OK') { 'ok' } else { 'bad' } }
    Latency = { param($v,$row) if ([int]"$v" -gt 1500) { 'warn' } else { '' } }
}
