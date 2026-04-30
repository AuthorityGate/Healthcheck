# Start of Settings
# End of Settings

$Title          = 'Distributed Port Group Binding Type'
$Header         = '[count] port group(s) using Ephemeral or Dynamic binding'
$Comments       = "vDS port group binding: Static (default, one port per VM) is correct for production. Dynamic (deprecated since 5.5) and Ephemeral (no binding state, lost across vCenter restart) are recovery-only. Ephemeral is the only binding that allows VM connect when vCenter is down - keep one ephemeral port group for vCenter-recovery scenarios but tag clearly."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'For each Dynamic port group: change to Static. For Ephemeral: confirm intentional (vCenter-recovery PG); document and tag.'

if (-not $Global:VCConnected) { return }

foreach ($pg in (Get-VDPortgroup -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $binding = $pg.PortBinding
        if ($binding -eq 'Ephemeral' -or $binding -eq 'Dynamic') {
            [pscustomobject]@{
                PortGroup = $pg.Name
                vDS       = if ($pg.VDSwitch) { $pg.VDSwitch.Name } else { '' }
                Binding   = $binding
                VLAN      = $pg.VlanConfiguration
                Note      = if ($binding -eq 'Dynamic') { 'Dynamic deprecated since vSphere 5.5; migrate to Static.' } else { 'Ephemeral binding - confirm intentional (vCenter-recovery use only).' }
            }
        }
    } catch { }
}

$TableFormat = @{
    Binding = { param($v,$row) if ($v -eq 'Dynamic') { 'bad' } elseif ($v -eq 'Ephemeral') { 'warn' } else { '' } }
}
