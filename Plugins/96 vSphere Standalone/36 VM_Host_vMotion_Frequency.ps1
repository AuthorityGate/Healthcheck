# Start of Settings
# End of Settings

$Title          = 'VM Host vMotion Frequency'
$Header         = 'VMs that vMotioned > 3 times in the last 24 hours'
$Comments       = 'Excessive vMotion = aggressive DRS or NUMA imbalance. Each vMotion is a brief stun.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Tune DRS migration threshold (default 3); investigate noisy-neighbor patterns.'

if (-not $Global:VCConnected) { return }
$start = (Get-Date).AddHours(-24)
$events = Get-VIEvent -Start $start -Types Info -MaxSamples 5000 -ErrorAction SilentlyContinue |
    Where-Object { $_.GetType().Name -eq 'VmMigratedEvent' -or $_.GetType().Name -eq 'DrsVmMigratedEvent' }
if (-not $events) { return }
$events | Group-Object { $_.Vm.Name } | Where-Object { $_.Count -gt 3 } | ForEach-Object {
    [pscustomobject]@{ VM=$_.Name; Migrations24h=$_.Count }
}
