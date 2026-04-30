# Start of Settings
# End of Settings

$Title          = 'Storage Capability Tag Consistency'
$Header         = '[count] datastore(s) without storage capability tags'
$Comments       = "Storage Policy Based Management (SPBM) uses datastore tags to map storage policies to capable datastores (e.g., 'Tier1', 'Replicated'). Untagged datastores cannot satisfy tag-based policies. Inventory which datastores have tags + which categories are missing."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Define a tag taxonomy (Tier1/Tier2/Tier3, Replicated, ProductionOnly, etc.) under Tags & Custom Attributes. Assign every datastore at least one tag. Build SPBM policies that consume those tags.'

if (-not $Global:VCConnected) { return }

foreach ($ds in (Get-Datastore -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $tags = @(Get-TagAssignment -Entity $ds -ErrorAction SilentlyContinue)
        if ($tags.Count -eq 0) {
            [pscustomobject]@{
                Datastore  = $ds.Name
                Type       = $ds.Type
                CapacityGB = [math]::Round($ds.CapacityGB,1)
                Tags       = '(none)'
            }
        }
    } catch { }
}
