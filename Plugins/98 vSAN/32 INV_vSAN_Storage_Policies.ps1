# Start of Settings
# End of Settings

$Title          = 'vSAN Storage Policies'
$Header         = 'All vSAN-tagged storage policies'
$Comments       = 'Inventory of every vSAN storage policy: name, FTT, fault tolerance method (RAID-1/5/6), stripe width, IOPS limit, default flag.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'Info'
$Recommendation = "Confirm the 'Default' policy is FTT >= 1 for production. Audit FTT=0 policies (lab use only)."

if (-not $Global:VCConnected) { return }
Get-SpbmStoragePolicy -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'vSAN' -or $_.Description -match 'VSAN' } | ForEach-Object {
    [pscustomobject]@{
        Policy     = $_.Name
        Description = $_.Description
        Default    = ($_.IsDefault -eq $true)
        AnyOfRules = $_.AnyOfRuleSets.Count
    }
}
