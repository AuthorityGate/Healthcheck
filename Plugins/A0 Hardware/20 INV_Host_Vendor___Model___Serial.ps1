# Start of Settings
# End of Settings

$Title          = 'Host Vendor / Model / Serial'
$Header         = 'Per-host hardware identity'
$Comments       = 'Vendor / model / serial / asset tag / chassis tag for every ESXi host. The base inventory record for asset reconciliation, warranty checks, and HCL lookups.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'Info'
$Recommendation = 'Cross-reference serial numbers with the vendor warranty portal annually.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_.ExtensionData.Hardware
    [pscustomobject]@{
        Host         = $_.Name
        Vendor       = $h.SystemInfo.Vendor
        Model        = $h.SystemInfo.Model
        SerialNumber = $h.SystemInfo.SerialNumber
        AssetTag     = ($h.SystemInfo.OtherIdentifyingInfo | Where-Object { $_.IdentifierType.Key -eq 'AssetTag' } | Select-Object -ExpandProperty IdentifierValue) -join ', '
        ServiceTag   = ($h.SystemInfo.OtherIdentifyingInfo | Where-Object { $_.IdentifierType.Key -eq 'ServiceTag' } | Select-Object -ExpandProperty IdentifierValue) -join ', '
        UUID         = $h.SystemInfo.Uuid
    }
}
