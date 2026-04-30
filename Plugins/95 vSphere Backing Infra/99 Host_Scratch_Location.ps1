# Start of Settings
# End of Settings

$Title          = 'Host Scratch Location'
$Header         = 'Per-host configured + current scratch location'
$Comments       = 'Reference: KB 1033696. Without persistent scratch, vmkernel logs are lost on reboot. Auto-deploy hosts often miss scratch config. Lists every host so operators can verify settings even when nothing is misconfigured.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = 'Set ScratchConfig.ConfiguredScratchLocation to a persistent VMFS / vSAN path. Reboot.'

if (-not $Global:VCConnected) { return }

$hosts = @(Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Note='Get-VMHost returned no hosts.' }
    return
}

foreach ($h in $hosts) {
    $cfg = (Get-AdvancedSetting -Entity $h -Name 'ScratchConfig.ConfiguredScratchLocation' -ErrorAction SilentlyContinue).Value
    $cur = (Get-AdvancedSetting -Entity $h -Name 'ScratchConfig.CurrentScratchLocation'   -ErrorAction SilentlyContinue).Value
    $isTmpfs    = ("$cur" -match '^/tmp' -or "$cur" -match 'scratch$' -and "$cfg" -ne "$cur")
    $isPersist  = ("$cur" -match '/vmfs/volumes/|nfs|vsanDatastore' -and "$cur" -notmatch 'tmpfs')
    $status = if ($isPersist -and -not $isTmpfs) { 'OK' }
              elseif ($isTmpfs)                  { 'TMPFS (logs lost at reboot)' }
              elseif (-not $cfg)                 { 'NO ConfiguredScratch set' }
              else                               { 'REVIEW' }
    [pscustomobject]@{
        Host              = $h.Name
        Cluster           = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
        ConfiguredScratch = if ($cfg) { "$cfg" } else { '(unset)' }
        CurrentScratch    = if ($cur) { "$cur" } else { '(unknown)' }
        Status            = $status
    }
}

$TableFormat = @{
    Status = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -match 'TMPFS|NO ') { 'bad' } elseif ("$v" -match 'REVIEW') { 'warn' } else { '' } }
}
