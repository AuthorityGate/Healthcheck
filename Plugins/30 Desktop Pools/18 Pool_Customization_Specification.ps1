# Start of Settings
# End of Settings

$Title          = 'Pool Customization / QuickPrep / Sysprep Specification'
$Header         = "[count] pool(s) with customization spec assigned"
$Comments       = @"
Each pool needs a customization specification so cloned VMs join AD with the right name and OU. Two methods:

- QuickPrep / ClonePrep (DEFAULT for instant-clone pools) - rapid customization tied to the parent VM, NO sysprep, no SID rotation. The standard for VDI today.
- Sysprep (full-clone pools) - slower (3-8 min per VM), full image generalization, used when the workload needs a unique SID.

Plugin probes both vSphere-managed and Nutanix-AHV-managed pools across multiple schema paths so the right spec shows up regardless of which Horizon MP backs the pool.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '30 Desktop Pools'
$Severity       = 'P3'
$Recommendation = "Instant-clone pools should show CustomizationType=QuickPrep. Full-clone pools should show CustomizationType=Sysprep. Empty CustomizationType = the pool was provisioned without customization (clones won't auto-join AD correctly). NamingPattern should encode pool/persona/site (e.g., VDI-WIN11-{n:fixed=4}) for inventory clarity."

if (-not (Get-HVRestSession)) { return }

# Walk a list of candidate property paths and return the first non-null match.
# Same pattern used by 45 Pool Deep Detail to handle vSphere vs Nutanix vs
# legacy linked-clone schema variations.
function Get-PoolNestedValue {
    param($Pool, [string[]]$Paths)
    foreach ($p in $Paths) {
        $segments = $p -split '\.'
        $cur = $Pool
        $ok = $true
        foreach ($s in $segments) {
            if ($null -eq $cur) { $ok = $false; break }
            try { $cur = $cur.$s } catch { $ok = $false; break }
            if ($null -eq $cur) { $ok = $false; break }
        }
        if ($ok -and $cur) { return $cur }
    }
    return $null
}

foreach ($p in (Get-HVDesktopPool)) {
    if (-not $p) { continue }

    # Customization spec name: either sysprep (full clone) or clone-prep
    # / QuickPrep (instant clone).
    $sysprepSpec = Get-PoolNestedValue -Pool $p -Paths @(
        'provisioning_settings.sysprep_customization_spec_id',
        'instant_clone_engine_provisioning_settings.sysprep_customization_spec_id',
        'vmware_provisioning_settings.sysprep_customization_spec_id',
        'nutanix_provisioning_settings.sysprep_customization_spec_id',
        'sysprep_customization_spec_id'
    )
    $cloneprepSpec = Get-PoolNestedValue -Pool $p -Paths @(
        'provisioning_settings.cloneprep_customization_spec_id',
        'instant_clone_engine_provisioning_settings.cloneprep_customization_spec_id',
        'vmware_provisioning_settings.cloneprep_customization_spec_id',
        'nutanix_provisioning_settings.cloneprep_customization_spec_id',
        'cloneprep_customization_spec_id'
    )
    $quickprepSpec = Get-PoolNestedValue -Pool $p -Paths @(
        'provisioning_settings.quickprep_customization_spec_id',
        'vmware_provisioning_settings.quickprep_customization_spec_id',
        'nutanix_provisioning_settings.quickprep_customization_spec_id',
        'quickprep_customization_spec_id'
    )
    $namingMethod = Get-PoolNestedValue -Pool $p -Paths @(
        'provisioning_settings.naming_method',
        'instant_clone_engine_provisioning_settings.naming_method',
        'vmware_provisioning_settings.naming_method',
        'nutanix_provisioning_settings.naming_method',
        'naming_method'
    )
    $namePattern = Get-PoolNestedValue -Pool $p -Paths @(
        'provisioning_settings.naming_pattern',
        'instant_clone_engine_provisioning_settings.naming_pattern',
        'vmware_provisioning_settings.naming_pattern',
        'nutanix_provisioning_settings.naming_pattern',
        'naming_pattern'
    )
    $adContainer = Get-PoolNestedValue -Pool $p -Paths @(
        'customization_settings.ad_container_rdn',
        'provisioning_settings.ad_container',
        'instant_clone_engine_provisioning_settings.ad_container',
        'vmware_customization_settings.ad_container_rdn',
        'nutanix_customization_settings.ad_container_rdn',
        'ad_container',
        'ad_container_rdn'
    )
    $separateDatastores = Get-PoolNestedValue -Pool $p -Paths @(
        'provisioning_settings.use_separate_datastores_replica_and_os_disks',
        'vmware_provisioning_settings.use_separate_datastores_replica_and_os_disks',
        'nutanix_provisioning_settings.use_separate_datastores_replica_and_os_disks',
        'use_separate_datastores_replica_and_os_disks'
    )

    # Determine the EFFECTIVE customization type. Instant-clone pools get
    # QuickPrep / ClonePrep automatically (no sysprep). Full-clone pools
    # use Sysprep with a vCenter customization spec.
    $custType = 'None'
    $custSpec = ''
    if ($cloneprepSpec) { $custType = 'ClonePrep / QuickPrep'; $custSpec = $cloneprepSpec }
    elseif ($quickprepSpec) { $custType = 'QuickPrep'; $custSpec = $quickprepSpec }
    elseif ($p.source -eq 'INSTANT_CLONE' -or $p.type -eq 'AUTOMATED' -and ($p.PSObject.Properties['instant_clone_engine_provisioning_settings'])) {
        $custType = 'QuickPrep (default for instant clones)'
    }
    elseif ($sysprepSpec) { $custType = 'Sysprep'; $custSpec = $sysprepSpec }

    [pscustomobject]@{
        Pool                  = if ($p.display_name) { $p.display_name } elseif ($p.name) { $p.name } else { $p.id }
        Source                = $p.source
        CustomizationType     = $custType
        SpecName              = $custSpec
        NamingMethod          = $namingMethod
        NamePattern           = $namePattern
        ADContainer           = $adContainer
        UseSeparateDatastores = $separateDatastores
    }
}

$TableFormat = @{
    CustomizationType = { param($v,$row)
        if ($v -match 'QuickPrep|ClonePrep') { 'ok' }
        elseif ($v -match 'Sysprep')          { 'ok' }
        elseif ($v -eq 'None')                { 'warn' }
        else { '' }
    }
}
