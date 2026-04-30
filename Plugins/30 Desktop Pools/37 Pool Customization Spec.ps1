# Start of Settings
# End of Settings

$Title          = 'Pool Guest Customization'
$Header         = '[count] pool(s) without a Sysprep / QuickPrep customization spec'
$Comments       = "Reference: 'Customize Guest Settings' (Horizon Admin Guide). A pool with no customization spec leaves child VMs un-domain-joined and breaks Horizon Agent registration."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '30 Desktop Pools'
$Severity       = 'P2'
$Recommendation = 'Pool -> Customization Specifications -> select a Sysprep (full clone) or QuickPrep (linked clone) spec.'

if (-not (Get-HVRestSession)) { return }
$pools = Get-HVDesktopPool
if (-not $pools) { return }

# Probe multiple paths since vSphere-managed and Nutanix-managed pools nest
# customization differently. Instant clones default to QuickPrep / ClonePrep
# (NO sysprep needed) so 'no spec' for an instant-clone pool means the pool
# was created without ANY customization, not that a Sysprep is missing.
function Get-CustValue {
    param($Pool, [string[]]$Paths)
    foreach ($p in $Paths) {
        $segs = $p -split '\.'
        $cur = $Pool; $ok = $true
        foreach ($s in $segs) { if ($null -eq $cur) { $ok=$false; break } ; try { $cur = $cur.$s } catch { $ok=$false; break } ; if ($null -eq $cur) { $ok=$false; break } }
        if ($ok -and $cur) { return $cur }
    }
    return $null
}

foreach ($p in $pools) {
    if (-not $p) { continue }
    # Effective customization type from any of the variant paths.
    $explicitType = Get-CustValue -Pool $p -Paths @(
        'customization_settings.customization_type',
        'vmware_customization_settings.customization_type',
        'nutanix_customization_settings.customization_type',
        'customization_type'
    )
    $sysSpec = Get-CustValue -Pool $p -Paths @(
        'provisioning_settings.sysprep_customization_spec_id',
        'instant_clone_engine_provisioning_settings.sysprep_customization_spec_id',
        'vmware_provisioning_settings.sysprep_customization_spec_id',
        'nutanix_provisioning_settings.sysprep_customization_spec_id',
        'sysprep_customization_spec_id'
    )
    $cloneSpec = Get-CustValue -Pool $p -Paths @(
        'provisioning_settings.cloneprep_customization_spec_id',
        'instant_clone_engine_provisioning_settings.cloneprep_customization_spec_id',
        'vmware_provisioning_settings.cloneprep_customization_spec_id',
        'nutanix_provisioning_settings.cloneprep_customization_spec_id',
        'cloneprep_customization_spec_id',
        'quickprep_customization_spec_id'
    )

    $effective = if ($cloneSpec) { 'QuickPrep / ClonePrep' }
                 elseif ($sysSpec) { 'Sysprep' }
                 elseif ($explicitType -and $explicitType -ne 'NONE') { $explicitType }
                 elseif ($p.source -eq 'INSTANT_CLONE') { 'QuickPrep (default for instant clones)' }
                 else { 'NONE' }

    # Only emit a row if NO customization was found - this plugin's purpose
    # is to surface the gap, not list every pool.
    if ($effective -eq 'NONE') {
        [pscustomobject]@{
            Pool = if ($p.name) { $p.name } elseif ($p.display_name) { $p.display_name } else { $p.id }
            Type = $p.type
            Source = $p.source
            CustomizationType = $effective
            Note = 'No QuickPrep, ClonePrep, or Sysprep spec found via any known schema path. Verify via Horizon Console -> Inventory -> Desktops -> <pool> -> Customization Specifications.'
        }
    }
}

