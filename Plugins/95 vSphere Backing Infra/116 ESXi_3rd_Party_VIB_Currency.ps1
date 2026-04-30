# Start of Settings

# Known-vendor VIB families. These get extra scrutiny: any VIB matching one
# of these prefixes is a 3rd-party agent that needs its own currency tracking
# alongside the ESXi base build.
$VendorPrefixes = @(
    @{ Vendor='Dell';     Pattern='^dell|^omsa|^idrac|^dellopenmanage|^dell-vib' }
    @{ Vendor='HPE';      Pattern='^hpe-?|^hp-?|^ilo|^smx-?|^cru-vib|^scsi-hpsa' }
    @{ Vendor='Cisco';    Pattern='^cisco-?|^ucs-?|^enic|^fnic' }
    @{ Vendor='NVIDIA';   Pattern='^nvidia|^nvidia-vgpu' }
    @{ Vendor='Mellanox'; Pattern='^nmlx|^mlx5|^mft' }
    @{ Vendor='Broadcom'; Pattern='^bnxt|^lpfc|^elxnet|^bcm-?' }
    @{ Vendor='Intel';    Pattern='^icen|^ixgben|^igbn|^i40en|^iavmd' }
    @{ Vendor='Pure';     Pattern='^pure-?' }
    @{ Vendor='NetApp';   Pattern='^netapp-?|^na-?' }
    @{ Vendor='EMC';      Pattern='^emc-?|^powerpath|^xtremio' }
    @{ Vendor='Veeam';    Pattern='^veeam' }
    @{ Vendor='Trend';    Pattern='^trendmicro|^deepsec' }
    @{ Vendor='Other3rd'; Pattern='^community|^thirdparty' }
)

# End of Settings

$Title          = 'ESXi 3rd-Party VIB Currency'
$Header         = "[count] 3rd-party VIB(s) detected across hosts (review for currency)"
$Comments       = "3rd-party VIBs (vendor agents, NIC drivers, storage drivers, GPU agents) are not on Broadcom's patch cadence. Each vendor has its own release schedule + lifecycle. Outdated 3rd-party VIBs accumulate CVEs and may stop working with newer ESXi versions. This list surfaces every 3rd-party VIB so a consultant can cross-check vendor support pages."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P3'
$Recommendation = "For each row, visit the vendor's support page (Dell DSU, HPE SUM, Cisco UCS, NVIDIA, etc.) and verify the VIB version matches the latest supported for your ESXi build. Schedule update during the next maintenance window."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue)) {
    if ($h.ConnectionState -ne 'Connected') { continue }
    try {
        $esxcli = Get-EsxCli -V2 -VMHost $h -ErrorAction Stop
        $vibs = $esxcli.software.vib.list.Invoke()
    } catch { continue }

    foreach ($v in $vibs) {
        $vendorMatch = $null
        foreach ($vp in $VendorPrefixes) {
            if ($v.Name -match $vp.Pattern) { $vendorMatch = $vp.Vendor; break }
        }
        if (-not $vendorMatch -and $v.Vendor -match 'VMware|VMW') { continue }   # skip VMware/Broadcom in-box
        if (-not $vendorMatch) { continue }                                      # not in our 3rd-party watch list

        # Compute install age - VIBs > 18 months old without update are candidates for review.
        $age = $null
        if ($v.InstallDate) {
            try { $age = [int]((Get-Date) - [datetime]$v.InstallDate).TotalDays } catch { $age = $null }
        }

        [pscustomobject]@{
            Host            = $h.Name
            Cluster         = if ($h.Parent) { $h.Parent.Name } else { '' }
            VendorFamily    = $vendorMatch
            Vendor          = $v.Vendor
            Name            = $v.Name
            Version         = $v.Version
            AcceptanceLevel = $v.AcceptanceLevel
            InstallDate     = $v.InstallDate
            AgeDays         = $age
            VendorPage      = switch ($vendorMatch) {
                'Dell'     { 'https://www.dell.com/support/home' }
                'HPE'      { 'https://support.hpe.com' }
                'Cisco'    { 'https://www.cisco.com/c/en/us/support' }
                'NVIDIA'   { 'https://docs.nvidia.com/grid/' }
                'Mellanox' { 'https://network.nvidia.com/support' }
                'Broadcom' { 'https://www.broadcom.com/support' }
                'Intel'    { 'https://www.intel.com/content/www/us/en/support' }
                'Pure'     { 'https://support.purestorage.com/' }
                'NetApp'   { 'https://mysupport.netapp.com/' }
                'EMC'      { 'https://www.dell.com/support/home/en-us/product-support/product/emc-powerpath' }
                'Veeam'    { 'https://www.veeam.com/support.html' }
                'Trend'    { 'https://success.trendmicro.com/' }
                default    { 'Vendor support page' }
            }
        }
    }
}

$TableFormat = @{
    AgeDays = { param($v,$row) if ($v -ne $null -and $v -gt 540) { 'bad' } elseif ($v -ne $null -and $v -gt 365) { 'warn' } else { '' } }
    AcceptanceLevel = { param($v,$row) if ($v -eq 'CommunitySupported') { 'warn' } else { '' } }
}
