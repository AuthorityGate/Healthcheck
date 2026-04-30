# Start of Settings
# End of Settings

$Title          = 'vSAN Cluster Full Configuration'
$Header         = 'Per-vSAN-cluster comprehensive config dump'
$Comments       = 'vSAN cluster type (OSA/ESA), encryption, dedupe-compression, slack space, fault domain config, witness host (stretched), file services. Every config field that influences sizing and supportability.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'Info'
$Recommendation = 'Snapshot whenever a major change occurs (host add, encryption rotation, etc.).'

if (-not $Global:VCConnected) { return }
Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.VsanEnabled } | ForEach-Object {
    $cl = $_
    $cfg = $cl.ExtensionData.ConfigurationEx.VsanConfigInfo
    $arch = if ($cfg -and $cfg.VsanEsaEnabled) { 'ESA' } else { 'OSA' }
    $u = $null
    try { $u = $cl | Get-VsanSpaceUsage -ErrorAction SilentlyContinue } catch { }
    [pscustomobject]@{
        Cluster              = $cl.Name
        Architecture         = $arch
        VsanEnabled          = $cfg.Enabled
        AutoClaimStorage     = $cfg.AutoClaimStorage
        DedupeEnabled        = if ($cfg.DataEfficiencyConfig) { $cfg.DataEfficiencyConfig.DedupEnabled } else { $false }
        CompressionEnabled   = if ($cfg.DataEfficiencyConfig) { $cfg.DataEfficiencyConfig.CompressionEnabled } else { $false }
        EncryptionEnabled    = if ($cfg.DataEncryptionConfig) { $cfg.DataEncryptionConfig.EncryptionEnabled } else { $false }
        KmsClusterId         = if ($cfg.DataEncryptionConfig -and $cfg.DataEncryptionConfig.KmsProviderId) { $cfg.DataEncryptionConfig.KmsProviderId.Id } else { '' }
        FaultDomains         = if ($cfg.FaultDomainsInfo) { @($cfg.FaultDomainsInfo).Count } else { 0 }
        StretchedCluster     = ($cfg.UnicastAgents -or $cfg.WitnessConfig)
        WitnessHost          = if ($cfg.WitnessConfig) { $cfg.WitnessConfig.HostId.Type + ':' + $cfg.WitnessConfig.HostId.Value } else { '' }
        FileServicesEnabled  = if ($cfg.FileServiceConfig) { $cfg.FileServiceConfig.Enabled } else { $false }
        TotalCapacityGB      = if ($u) { [math]::Round($u.TotalCapacityGB,1) } else { 'n/a' }
        FreeSpaceGB          = if ($u) { [math]::Round($u.FreeSpaceGB,1) } else { 'n/a' }
        UsedPct              = if ($u -and $u.TotalCapacityGB -gt 0) { [math]::Round((($u.TotalCapacityGB - $u.FreeSpaceGB)/$u.TotalCapacityGB)*100, 1) } else { 'n/a' }
    }
}
