# Start of Settings
# End of Settings

$Title          = 'Pool Delete Pattern (Floating)'
$Header         = "[count] floating pool(s) without 'Delete on Logoff' set"
$Comments       = "Reference: 'Configure Floating Pool Settings'. Floating pools should reset on logoff for security + image freshness."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '30 Desktop Pools'
$Severity       = 'P3'
$Recommendation = "Pool -> Edit -> 'Delete or Refresh machines on logoff' -> 'Delete'."

if (-not (Get-HVRestSession)) { return }
$pools = Get-HVDesktopPool
if (-not $pools) { return }
foreach ($p in $pools) {
    if ($p.user_assignment -eq 'FLOATING') {
        $del = $null
        if ($p.provisioning_settings -and $p.provisioning_settings.delete_after_logoff) { $del = $p.provisioning_settings.delete_after_logoff }
        if ($p.instant_clone_engine_provisioning_settings -and $p.instant_clone_engine_provisioning_settings.delete_after_logoff) { $del = $p.instant_clone_engine_provisioning_settings.delete_after_logoff }
        if (-not $del) {
            [pscustomobject]@{ Pool=$p.name; Type=$p.type; Source=$p.source; UserAssignment=$p.user_assignment; DeleteOnLogoff=$del }
        }
    }
}
