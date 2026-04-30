# Start of Settings
# Treat any VM with a Custom Attribute Tier=Critical OR a folder named like
# 'Production' or 'Critical' as a critical workload that should have memory
# reservation set.
$CriticalFolderRegex = 'Production|Critical|Tier-?1|PROD'
# End of Settings

$Title          = 'Critical VMs Without Memory Reservation'
$Header         = '[count] critical VM(s) with zero memory reservation'
$Comments       = "Critical workloads should hold a non-zero memory reservation so they cannot be ballooned/swapped under cluster memory pressure. Identifies VMs in production folders / critical tags with reservation=0. Pair with shares for relative priority."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = "VM -> Edit Settings -> Resources -> Memory -> Reservation = configured RAM (or a documented fraction). Combine with cluster admission control to enforce capacity."

if (-not $Global:VCConnected) { return }

foreach ($vm in (Get-VM -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $folder = if ($vm.Folder) { $vm.Folder.Name } else { '' }
        $isCritical = $folder -match $CriticalFolderRegex
        if (-not $isCritical) { continue }
        $rp = $vm.ExtensionData.ResourceConfig
        $memReserve = $rp.MemoryAllocation.Reservation
        if ($memReserve -eq 0) {
            [pscustomobject]@{
                VM             = $vm.Name
                Folder         = $folder
                ConfiguredMB   = $vm.MemoryMB
                ReservationMB  = $memReserve
                Note           = 'Production-folder VM has no memory reservation - exposed to balloon/swap during contention.'
            }
        }
    } catch { }
}

$TableFormat = @{
    ReservationMB = { param($v,$row) if ([int]$v -eq 0) { 'warn' } else { '' } }
}
