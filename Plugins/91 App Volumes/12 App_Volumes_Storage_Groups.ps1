# Start of Settings
# End of Settings

$Title          = 'App Volumes Storage Groups'
$Header         = '[count] storage group(s) defined'
$Comments       = 'Storage groups parallel-distribute volumes across multiple datastores.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'Info'
$Recommendation = "Verify each storage group's member datastores are uniformly capped and accessible."

if (-not (Get-AVRestSession)) { return }
$sg = Get-AVStorageGroup
if (-not $sg) { return }
foreach ($g in $sg.storage_groups) {
    [pscustomobject]@{
        Name           = $g.name
        Strategy       = $g.strategy
        TemplateCount  = $g.template_count
        AutoImport     = $g.auto_import
        AutoReplicate  = $g.auto_replicate
        Datastores     = ($g.member_datastores -join ', ')
    }
}
