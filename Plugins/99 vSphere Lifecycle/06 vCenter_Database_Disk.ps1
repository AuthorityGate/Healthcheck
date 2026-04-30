# Start of Settings
# End of Settings

$Title          = 'vCenter Database Disk'
$Header         = 'vCenter PostgreSQL DB disk health'
$Comments       = 'vCenter DB free space < 30% delays vpxd start; auto-shrink not always sufficient.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P2'
$Recommendation = "VAMI -> Database -> verify partition utilization. Apply 'reduce-database-size' KB."

if (-not $Global:VCConnected) { return }
[pscustomobject]@{ Note = 'Run on VCSA: df -h /storage/db . Beyond PowerCLI scope.'; Reference = 'KB 2147154' }
