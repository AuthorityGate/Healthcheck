# Start of Settings
# End of Settings

$Title          = 'Pool Display Protocol + Allow Override'
$Header         = 'Per-pool default display protocol + whether users can override'
$Comments       = "Default display protocol determines what every session uses unless the user explicitly picks. Blast Extreme is recommended for VDI (TCP 8443 / UDP 4172, hardware H.264/HEVC offload, NVENC GPU acceleration support); PCoIP for legacy use; RDP only for fallback / IT scenarios. Allowing user-override is a UX win but creates protocol fragmentation in the network capture / SIEM."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '30 Desktop Pools'
$Severity       = 'P3'
$Recommendation = 'Default = Blast Extreme on every pool unless documented constraint. Disallow user override on production pools to keep one supported protocol per pool / one set of UAG ports tightened.'

if (-not (Get-HVRestSession)) { return }
$pools = @(Get-HVDesktopPool)
if (-not $pools) { return }

function Get-HVPoolNested {
    param($Pool, [string[]]$Paths)
    foreach ($p in $Paths) {
        $segs = $p -split '\.'
        $cur = $Pool
        $ok = $true
        foreach ($s in $segs) {
            if ($null -eq $cur) { $ok = $false; break }
            try { $cur = $cur.$s } catch { $ok = $false; break }
            if ($null -eq $cur) { $ok = $false; break }
        }
        if ($ok -and $null -ne $cur) { return $cur }
    }
    return $null
}

foreach ($p in $pools) {
    if (-not $p) { continue }
    $name = if ($p.name) { "$($p.name)" } else { "$($p.id)" }
    $defaultProto = Get-HVPoolNested $p @(
        'desktop_settings.display_protocol_settings.default_display_protocol',
        'display_protocol_settings.default_display_protocol',
        'default_display_protocol'
    )
    $allowOverride = Get-HVPoolNested $p @(
        'desktop_settings.display_protocol_settings.allow_users_to_choose_protocol',
        'display_protocol_settings.allow_users_to_choose_protocol',
        'allow_users_to_choose_protocol'
    )
    $supports3D = Get-HVPoolNested $p @(
        'desktop_settings.display_protocol_settings.enable_grid_vgpus',
        'display_protocol_settings.enable_grid_vgpus',
        'enable_grid_vgpus'
    )
    $vGpuProfile = Get-HVPoolNested $p @(
        'vcenter_provisioning_settings.virtual_center_managed_common_settings.shared_pci_devices.0.profile',
        'shared_pci_devices.0.profile'
    )
    $supportedProtos = Get-HVPoolNested $p @(
        'desktop_settings.display_protocol_settings.supported_display_protocols',
        'display_protocol_settings.supported_display_protocols'
    )

    $protoStr = if ($defaultProto) { "$defaultProto" } else { '(unset)' }
    $status = if ($protoStr -match 'BLAST') { 'OK (Blast Extreme)' }
              elseif ($protoStr -match 'PCOIP') { 'INFO (PCoIP - consider Blast)' }
              elseif ($protoStr -match 'RDP') { 'WARN (RDP default - poor UX over WAN)' }
              elseif ($protoStr -eq '(unset)') { 'NOT QUERIED' }
              else { "REVIEW ($protoStr)" }

    [pscustomobject]@{
        Pool             = $name
        Type             = if ($p.type) { "$($p.type)" } else { '' }
        DefaultProtocol  = $protoStr
        AllowUserChoose  = if ($null -ne $allowOverride) { [bool]$allowOverride } else { '' }
        SupportedProtocols = if ($supportedProtos) { ($supportedProtos -join ', ') } else { '' }
        VGpuEnabled      = if ($null -ne $supports3D) { [bool]$supports3D } else { '' }
        VGpuProfile      = if ($vGpuProfile) { "$vGpuProfile" } else { '' }
        Status           = $status
    }
}

$TableFormat = @{
    DefaultProtocol = { param($v,$row) if ("$v" -match 'BLAST') { 'ok' } elseif ("$v" -match 'RDP') { 'warn' } else { '' } }
    Status          = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'WARN|REVIEW|NOT') { 'warn' } else { '' } }
}
