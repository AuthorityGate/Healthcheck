# Start of Settings
# End of Settings

$Title          = 'vSAN Default Storage Policy'
$Header         = 'Default vSAN storage policy'
$Comments       = 'Newly-created vSAN VMs inherit the default policy. Verify FTT >= 1, hostFailures > 0.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'P2'
$Recommendation = 'Tighten default policy (FTT=1, RAID-1 mirror) for production clusters.'

if (-not $Global:VCConnected) { return }
$pols = Get-SpbmStoragePolicy -ErrorAction SilentlyContinue
if (-not $pols) { return }
$pols | Where-Object { $_.Name -match 'vSAN' } | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{
        Policy        = $_.Name
        Description   = $_.Description
        Default       = ($_.IsDefault -eq $true)
    }
}
