# Start of Settings
# End of Settings

$Title          = 'DRS Automation Level'
$Header         = 'Per-cluster DRS automation level (FullyAutomated recommended for production)'
$Comments       = 'Lists every DRS-enabled cluster with its current automation level. DRS at Manual/PartiallyAutomated requires operator approval for migrations - effectively load-balances only at VM power-on. Production clusters typically should be FullyAutomated. Clusters with DRS disabled are listed as well so operators can confirm intent.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.1
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = 'Cluster -> Configure -> vSphere DRS -> Edit -> Automation Level = Fully Automated. Use VM-level overrides if specific VMs must stay manual.'

if (-not $Global:VCConnected) { return }

$clusters = @(Get-Cluster -ErrorAction SilentlyContinue | Sort-Object Name)
if ($clusters.Count -eq 0) {
    [pscustomobject]@{ Note = 'No clusters returned by Get-Cluster (vCenter may not be connected, or the audit account lacks Read on cluster objects).' }
    return
}

foreach ($c in $clusters) {
    [pscustomobject]@{
        Cluster         = $c.Name
        DrsEnabled      = [bool]$c.DrsEnabled
        AutomationLevel = if ($c.DrsEnabled) { "$($c.DrsAutomationLevel)" } else { 'n/a (DRS off)' }
        Recommended     = 'FullyAutomated'
        Status          = if (-not $c.DrsEnabled) { 'DRS OFF' }
                          elseif ($c.DrsAutomationLevel -eq 'FullyAutomated') { 'OK' }
                          else { 'NON-DEFAULT' }
        HostCount       = @($c | Get-VMHost -ErrorAction SilentlyContinue).Count
    }
}

$TableFormat = @{
    AutomationLevel = { param($v,$row) if ("$v" -match 'n/a') { 'warn' } elseif ("$v" -ne 'FullyAutomated') { 'warn' } else { '' } }
    DrsEnabled      = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
    Status          = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -match 'OFF|NON-DEFAULT') { 'warn' } else { '' } }
}
