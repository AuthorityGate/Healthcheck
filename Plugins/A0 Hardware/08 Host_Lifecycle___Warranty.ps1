# Start of Settings
# End of Settings

$Title          = 'Host Lifecycle / Warranty'
$Header         = 'Hardware vendor + warranty hint'
$Comments       = 'Hosts off-warranty = no firmware updates. Audit annually.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'P3'
$Recommendation = 'Cross-reference serial numbers with vendor warranty portal. Archive off-warranty hosts.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        Host         = $_.Name
        Vendor       = $_.Manufacturer
        Model        = $_.Model
        SerialNumber = $_.ExtensionData.Hardware.SystemInfo.SerialNumber
        AssetTag     = $_.ExtensionData.Hardware.SystemInfo.OtherIdentifyingInfo | Where-Object { $_.IdentifierType.Key -eq 'AssetTag' } | Select-Object -ExpandProperty IdentifierValue
    }
}
