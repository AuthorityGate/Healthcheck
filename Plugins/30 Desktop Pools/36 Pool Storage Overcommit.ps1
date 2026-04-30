# Start of Settings
# End of Settings

$Title          = 'Pool Storage Overcommit Setting'
$Header         = '[count] pool(s) using AGGRESSIVE storage overcommit'
$Comments       = "Reference: 'Storage Overcommit' (Horizon Admin Guide). 'Aggressive' overcommit on slow tier-3 storage causes IO storms."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '30 Desktop Pools'
$Severity       = 'P3'
$Recommendation = "Set storage overcommit to 'Conservative' or 'Moderate' for tier-3 datastores. Reserve 'Aggressive' for SSD-backed VSAN ESA."

if (-not (Get-HVRestSession)) { return }
$pools = Get-HVDesktopPool
if (-not $pools) { return }
foreach ($p in $pools) {
    $oc = $null
    if ($p.provisioning_settings -and $p.provisioning_settings.storage_overcommit) { $oc = $p.provisioning_settings.storage_overcommit }
    if ($oc -eq 'AGGRESSIVE') {
        [pscustomobject]@{ Pool=$p.name; Type=$p.type; Source=$p.source; Overcommit=$oc }
    }
}

