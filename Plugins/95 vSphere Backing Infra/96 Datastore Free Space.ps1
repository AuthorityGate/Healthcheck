# Start of Settings
# Datastores below this free-percent are reported.
$DatastoreFreePctThreshold = 15
# End of Settings

$Title          = "Low-Free-Space Datastores"
$Header         = "[count] datastore(s) below $DatastoreFreePctThreshold% free"
$Comments       = "Instant-clone replicas, swap files, and event-DB growth fill VMFS/VSAN datastores quickly. Below 10% free, instant-clone provisioning fails."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "95 vSphere Backing Infra"
$Severity       = "P1"
$Recommendation = "Reclaim space (delete unused replicas, expire snapshots, run UNMAP) or expand the datastore. For VSAN, verify storage policy headroom."

if (-not $Global:VCConnected) { return }

Get-Datastore -ErrorAction SilentlyContinue | ForEach-Object {
    $freePct = if ($_.CapacityGB -gt 0) { [math]::Round(($_.FreeSpaceGB / $_.CapacityGB) * 100, 1) } else { 0 }
    if ($freePct -lt $DatastoreFreePctThreshold) {
        [pscustomobject]@{
            Datastore  = $_.Name
            Type       = $_.Type
            CapacityGB = [math]::Round($_.CapacityGB,1)
            FreeGB     = [math]::Round($_.FreeSpaceGB,1)
            FreePct    = $freePct
        }
    }
} | Sort-Object FreePct

$TableFormat = @{
    FreePct = { param($v,$row) if ([double]$v -lt 5) { 'bad' } elseif ([double]$v -lt 15) { 'warn' } else { '' } }
}
