# Start of Settings
# End of Settings

$Title          = 'Pool Spare-Machine Drift'
$Header         = '[count] floating-pool(s) configured with insufficient spare machines'
$Comments       = "Reference: 'Configure Spare Machines'. A floating pool needs spare desktops for fast logon. Recommendation: spare >= 5% of max or 2, whichever is higher."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '30 Desktop Pools'
$Severity       = 'P3'
$Recommendation = "Provisioning Settings -> 'Number of spare (powered on) machines'. Set 5% of max or 2 minimum."

if (-not (Get-HVRestSession)) { return }
$pools = Get-HVDesktopPool
if (-not $pools) { return }
foreach ($p in $pools) {
    if ($p.user_assignment -ne 'FLOATING') { continue }
    $max = if ($p.provisioning_settings) { $p.provisioning_settings.max_number_of_machines } else { 0 }
    $spare = if ($p.provisioning_settings) { $p.provisioning_settings.number_of_spare_machines } else { 0 }
    $minSpare = [math]::Max(2, [int]($max * 0.05))
    if ($spare -lt $minSpare) {
        [pscustomobject]@{ Pool=$p.name; Max=$max; Spare=$spare; RecommendedMin=$minSpare }
    }
}

