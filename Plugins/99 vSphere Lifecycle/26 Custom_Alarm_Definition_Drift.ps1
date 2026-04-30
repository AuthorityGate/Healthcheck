# Start of Settings
# End of Settings

$Title          = 'Custom Alarm Definitions Inventory'
$Header         = '[count] custom (non-default) alarm definition(s)'
$Comments       = 'vCenter ships with ~80 default alarms. Custom alarms = ones the customer has added. Inventory: name, severity, target object type, action. High custom-alarm count usually means alarm noise; review for staleness.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'Info'
$Recommendation = 'Audit each custom alarm: is it still useful? does the destination address still exist? Disable / delete dead alarms to reduce notification fatigue.'

if (-not $Global:VCConnected) { return }

try {
    $alarms = Get-AlarmDefinition -ErrorAction Stop
    foreach ($a in $alarms) {
        # Heuristic for "non-default": SystemDefined property is false on
        # custom alarms in newer PowerCLI; fall back to name-not-starting-with
        # standard prefix.
        $isCustom = $false
        try { $isCustom = -not [bool]$a.ExtensionData.SystemDefined } catch { }
        if (-not $isCustom -and $a.Name -notmatch '^(Host |VM |Datastore |Cluster )') { $isCustom = $true }
        if ($isCustom) {
            [pscustomobject]@{
                AlarmName = $a.Name
                Enabled   = $a.Enabled
                Description = $a.Description
                EntityType = $a.ExtensionData.Info.EntityType
                ActionCount = @($a.ExtensionData.Info.Action).Count
            }
        }
    }
} catch { }
