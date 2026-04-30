# Start of Settings
# End of Settings

$Title          = "ESXi Hardware Inventory"
$Header         = "[count] host(s) with vendor / model / CPU / RAM / NIC count"
$Comments       = "Vendor, model, CPU SKU, socket count, total cores, total RAM, NIC count for every host. Used for refresh planning + identifying outliers (mismatched hardware in same cluster degrades DRS efficiency)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "Info"
$Recommendation = "Mixed CPU SKUs across a cluster require EVC mode pinned to the lowest-common feature set (CPU + memory headroom planning). Storage attachments differ by vendor: NVMe vs SAS-only counsels different vSAN/vVol planning."

if (-not $Global:VCConnected) { return }
$hosts = @(Get-VMHost -ErrorAction SilentlyContinue)
foreach ($h in $hosts) {
    if (-not $h) { continue }
    $info = $null
    try { $info = Get-View $h.Id -Property 'Hardware','Summary' -ErrorAction Stop } catch { }
    [pscustomobject]@{
        Host       = $h.Name
        Cluster    = if ($h.Parent) { $h.Parent.Name } else { '' }
        Vendor     = if ($info) { $info.Hardware.SystemInfo.Vendor } else { '' }
        Model      = if ($info) { $info.Hardware.SystemInfo.Model } else { '' }
        CpuSku     = if ($info -and $info.Summary.Hardware.CpuModel) { $info.Summary.Hardware.CpuModel } else { '' }
        Sockets    = if ($info) { $info.Hardware.CpuInfo.NumCpuPackages } else { '' }
        Cores      = $h.NumCpu
        Threads    = if ($info) { $info.Hardware.CpuInfo.NumCpuThreads } else { '' }
        RAMGB      = [math]::Round($h.MemoryTotalGB, 0)
        NICs       = if ($info) { @($info.Hardware.NetworkInfo.Pnic).Count } else { '' }
        HBAs       = if ($info) { @($info.Hardware.HBAInfo).Count } else { '' }
        BIOSDate   = if ($info) { $info.Hardware.BiosInfo.ReleaseDate } else { '' }
    }
}
