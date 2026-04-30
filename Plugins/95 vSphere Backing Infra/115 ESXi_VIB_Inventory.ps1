# Start of Settings
# End of Settings

$Title          = 'ESXi VIB Inventory'
$Header         = 'Per-host VIB (vSphere Installation Bundle) inventory'
$Comments       = "Lists every VIB on every host with vendor, version, install date, and acceptance level. Surfaces 3rd-party VIBs (Dell OMSA, HPE Insight, Cisco UCS, NSX kernel modules, NVIDIA vGPU, EMC PowerPath, Pure Storage, NetApp, etc.) so the consultant can audit what's running, identify uncommon VIBs, and verify the host's signature trust posture."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'Info'
$Recommendation = "Review the VIB inventory against your approved-vendor list. CommunitySupported acceptance level is acceptable for vendor tools but should be documented; PartnerSupported and VMwareCertified are the supported defaults. Any VIB you cannot identify the source of is a red flag."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue)) {
    if ($h.ConnectionState -ne 'Connected') { continue }
    try {
        $esxcli = Get-EsxCli -V2 -VMHost $h -ErrorAction Stop
        $vibs = $esxcli.software.vib.list.Invoke()
    } catch {
        [pscustomobject]@{
            Host = $h.Name; Vendor = '(esxcli unreachable)'; Name = ''; Version = ''
            AcceptanceLevel = ''; InstallDate = ''; ID = ''
        }
        continue
    }

    foreach ($v in $vibs) {
        [pscustomobject]@{
            Host            = $h.Name
            Cluster         = if ($h.Parent) { $h.Parent.Name } else { '' }
            Vendor          = $v.Vendor
            Name            = $v.Name
            Version         = $v.Version
            AcceptanceLevel = $v.AcceptanceLevel
            InstallDate     = $v.InstallDate
            ID              = $v.ID
        }
    }
}

$TableFormat = @{
    AcceptanceLevel = { param($v,$row) if ($v -eq 'CommunitySupported') { 'warn' } else { '' } }
}
