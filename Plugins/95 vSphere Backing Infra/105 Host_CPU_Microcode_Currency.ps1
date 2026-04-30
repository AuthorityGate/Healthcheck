# Start of Settings
# End of Settings

$Title          = 'Host CPU Microcode Currency'
$Header         = 'ESXi CPU microcode advisory'
$Comments       = 'Reference: VMSA bulletins (Spectre/Meltdown/MMIO). Out-of-date microcode leaves the host vulnerable to side-channel attacks.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = 'Patch ESXi to current build OR apply CPU microcode update via BIOS firmware update.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $bios = $_.ExtensionData.Hardware.BiosInfo
    [pscustomobject]@{
        Host        = $_.Name
        Build       = $_.Build
        BiosVersion = $bios.BiosVersion
        BiosDate    = $bios.ReleaseDate
        Vendor      = $_.Manufacturer
        Model       = $_.Model
    }
}
