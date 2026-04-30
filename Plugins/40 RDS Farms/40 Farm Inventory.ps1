# Start of Settings
# End of Settings

$Title          = "RDS Farm Inventory"
$Header         = "[count] RDS farm(s)"
$Comments       = "All RDS farms with type, load-balancing settings, and session limit per host."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "40 RDS Farms"
$Severity       = "Info"

$farms = Get-HVFarm
if (-not $farms) { return }

foreach ($f in $farms) {
    [pscustomobject]@{
        Name              = $f.name
        Type              = $f.type
        Source            = $f.source
        Enabled           = $f.enabled
        LoadBalancing     = if ($f.load_balancer_settings) { $f.load_balancer_settings.use_view_load_balancing } else { $false }
        DefaultProtocol   = $f.default_display_protocol
        SessionLimitHost  = if ($f.session_settings) { $f.session_settings.max_sessions_count } else { '' }
        ServerCount       = if ($f.server_count) { $f.server_count } else { 0 }
    }
}

$TableFormat = @{
    Enabled = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
}
