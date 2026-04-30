# Start of Settings
# End of Settings

$Title          = 'Persistent Memory (PMem) State'
$Header         = '[count] host(s) with Persistent Memory inventory'
$Comments       = "Per-host Intel Optane / PMem capacity + mode. PMem can run in App Direct (block-addressable storage) or Memory Mode (DRAM cache + PMem main memory). VMware supports App Direct for VM-direct passthrough; Memory Mode treats PMem as RAM transparently."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'Info'
$Recommendation = 'Note: Intel Optane was discontinued in 2022. Existing fleets continue to operate; plan migration off PMem for new builds.'

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        # PMem datastore reports as type 'PMEM'
        $pmem = @($h | Get-Datastore -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'PMEM' })
        foreach ($p in $pmem) {
            [pscustomobject]@{
                Host        = $h.Name
                Datastore   = $p.Name
                CapacityGB  = [math]::Round($p.CapacityGB,1)
                FreeGB      = [math]::Round($p.FreeSpaceGB,1)
                Type        = $p.Type
                Note        = 'Persistent Memory present.'
            }
        }
    } catch { }
}
