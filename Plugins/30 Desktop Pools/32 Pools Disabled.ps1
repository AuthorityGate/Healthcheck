# Start of Settings
# End of Settings

$Title          = "Disabled Pools"
$Header         = "[count] pool(s) disabled"
$Comments       = "Disabled pools deny new sessions. Confirm whether each is intentionally disabled (decommission) or stuck disabled (admin oversight)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "30 Desktop Pools"
$Severity       = "P3"
$Recommendation = "If disablement is intentional and permanent, delete the pool to avoid clutter. Otherwise re-enable."

$pools = Get-HVDesktopPool
if (-not $pools) { return }

foreach ($p in $pools) {
    if (-not $p.enabled) {
        [pscustomobject]@{
            Name           = $p.name
            Type           = $p.type
            Source         = $p.source
            UserAssignment = $p.user_assignment
            Description    = $p.description
        }
    }
}
