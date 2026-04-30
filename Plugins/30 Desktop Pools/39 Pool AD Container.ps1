# Start of Settings
# End of Settings

$Title          = 'Pool AD Container Compliance'
$Header         = 'Pool target AD OU inventory'
$Comments       = "Pools should drop child VMs into a dedicated OU with GPO inheritance blocked from inheritance-noisy parent OUs (e.g., a flat 'Computers' container)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '30 Desktop Pools'
$Severity       = 'P3'
$Recommendation = "Set OU per pool. Apply a Horizon-specific GPO scope; delete leftover stale machine accounts via 'Pending Deletion'."

if (-not (Get-HVRestSession)) { return }
$pools = Get-HVDesktopPool
if (-not $pools) { return }
foreach ($p in $pools) {
    $ou = $null
    if ($p.customization_settings -and $p.customization_settings.ad_container) { $ou = $p.customization_settings.ad_container }
    if ($ou) {
        [pscustomobject]@{ Pool=$p.name; ADContainer=$ou }
    }
}

