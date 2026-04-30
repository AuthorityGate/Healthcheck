# Start of Settings
# End of Settings

$Title          = "Application Pools"
$Header         = "[count] application pool(s) published"
$Comments       = "Inventory of all published applications, the farm hosting them, and their entitlement state."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "40 RDS Farms"
$Severity       = "Info"

$apps = Get-HVApplicationPool
if (-not $apps) { return }

foreach ($a in $apps) {
    [pscustomobject]@{
        Name           = $a.name
        DisplayName    = $a.display_name
        FarmName       = $a.farm_name
        ExecutablePath = $a.executable_path
        Version        = $a.version
        Publisher      = $a.publisher
        Enabled        = $a.enabled
        Auto           = $a.auto_update_file_types
    }
}

$TableFormat = @{
    Enabled = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
}
