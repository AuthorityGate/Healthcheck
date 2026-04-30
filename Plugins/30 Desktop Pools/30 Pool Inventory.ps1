# Start of Settings
# End of Settings

$Title          = "Desktop Pool Inventory"
$Header         = "[count] desktop pool(s)"
$Comments       = "Inventory of every desktop pool with type, source (instant-clone, full-clone, manual), enablement, and provisioning status."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "30 Desktop Pools"
$Severity       = "Info"

$pools = Get-HVDesktopPool
if (-not $pools) { return }

foreach ($p in $pools) {
    [pscustomobject]@{
        Name              = $p.name
        DisplayName       = $p.display_name
        Type              = $p.type
        Source            = $p.source
        UserAssignment    = $p.user_assignment
        Enabled           = $p.enabled
        Provisioning      = if ($p.provisioning_status_data) { $p.provisioning_status_data.provisioning_state } else { '' }
        MachineNamingType = if ($p.pattern_naming_settings) { 'Pattern' } elseif ($p.specified_names) { 'Specified' } else { '' }
    }
}

$TableFormat = @{
    Enabled       = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
    Provisioning  = { param($v,$row) if ($v -and $v -notin 'PROVISIONING','READY','PROVISIONING_DISABLED','') { 'bad' } else { '' } }
}
