# Start of Settings
# End of Settings

$Title          = 'Pool Capacity Saturation'
$Header         = '[count] pool(s) operating > 90% of configured maximum'
$Comments       = "Pools running close to MaxNumberOfMachines cannot satisfy login surges. Compare 'machines existing' vs 'configured max'."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '30 Desktop Pools'
$Severity       = 'P2'
$Recommendation = 'Increase pool max size, or add a second pool, or migrate to floating from dedicated to recycle desktops.'

if (-not (Get-HVRestSession)) { return }
$pools = Get-HVDesktopPool
if (-not $pools) { return }
foreach ($p in $pools) {
    $max = if ($p.provisioning_settings) { $p.provisioning_settings.max_number_of_machines } else { 0 }
    $cur = if ($p.machine_count) { $p.machine_count } else { 0 }
    if ($max -gt 0) {
        $pct = [math]::Round(($cur / $max) * 100, 1)
        if ($pct -ge 90) {
            [pscustomobject]@{ Pool=$p.name; Current=$cur; Max=$max; PercentFull=$pct }
        }
    }
}

