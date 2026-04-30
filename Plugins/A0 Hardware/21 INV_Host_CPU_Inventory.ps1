# Start of Settings
# End of Settings

$Title          = 'Host CPU Inventory'
$Header         = 'Per-host CPU model + sockets + cores + speed'
$Comments       = 'Detailed CPU inventory: vendor, brand string, sockets, cores per socket, threads per core, MHz, hyperthreading state. Use this for license-counting (per-CPU vs per-core) and capacity planning.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'Info'
$Recommendation = 'Snapshot annually for asset records.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_.ExtensionData
    $cpu = $h.Hardware.CpuPkg | Select-Object -First 1
    [pscustomobject]@{
        Host          = $_.Name
        CpuVendor     = $cpu.Vendor
        CpuBrand      = $cpu.Description
        Sockets       = $h.Hardware.CpuInfo.NumCpuPackages
        CoresPerSocket = $h.Hardware.CpuInfo.NumCpuCores / $h.Hardware.CpuInfo.NumCpuPackages
        TotalCores    = $h.Hardware.CpuInfo.NumCpuCores
        TotalThreads  = $h.Hardware.CpuInfo.NumCpuThreads
        ClockMHz      = $h.Hardware.CpuInfo.Hz / 1000000
        HyperThreading = $_.HyperthreadingActive
    }
}
