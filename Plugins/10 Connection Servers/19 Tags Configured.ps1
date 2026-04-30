# Start of Settings
# End of Settings

$Title          = 'Connection Server Tags'
$Header         = 'Tag-based pool restriction inventory'
$Comments       = "Reference: Horizon Admin Guide -> 'Restrict Pool Access by Tag'. Tags map UAG / external / internal CSes to specific pools (DMZ vs internal). Missing tags collapse this segregation."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'P3'
$Recommendation = "Tag each CS by access method (e.g. 'external','internal') and assign tags to pools accordingly."

if (-not (Get-HVRestSession)) { return }
$cs = Get-HVConnectionServer
if (-not $cs) { return }
foreach ($c in $cs) {
    [pscustomobject]@{
        Name = $c.name
        Tags = ($c.tags -join ', ')
        Note = if (-not $c.tags) { 'No tags configured' } else { '' }
    }
}

