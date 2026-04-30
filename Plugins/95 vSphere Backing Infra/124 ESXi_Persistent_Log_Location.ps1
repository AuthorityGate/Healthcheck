# Start of Settings
# End of Settings

$Title          = 'ESXi Persistent Log Location'
$Header         = 'Per-host scratch path classification (persistent / tmpfs)'
$Comments       = "Default /scratch on USB/SD-boot installs is a tmpfs ramdisk - logs are lost at reboot. Persistent /scratch on a reliable datastore = forensic data survives reboots. Lists every host so operators can verify the audit ran."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Configure ScratchConfig.ConfiguredScratchLocation to a persistent datastore path. Combine with remote syslog forwarding for full forensic coverage."

if (-not $Global:VCConnected) { return }

$hosts = @(Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Note='Get-VMHost returned no hosts.' }
    return
}

foreach ($h in $hosts) {
    if ($h.ConnectionState -ne 'Connected') {
        [pscustomobject]@{ Host=$h.Name; Cluster=if ($h.Parent) { "$($h.Parent.Name)" } else { '' }; ConfiguredLocation=''; CurrentLocation=''; Status='SKIPPED (disconnected)' }
        continue
    }
    $cfg = ''
    $cur = ''
    try {
        $cfg = (Get-AdvancedSetting -Entity $h -Name 'ScratchConfig.ConfiguredScratchLocation' -ErrorAction SilentlyContinue).Value
        $cur = (Get-AdvancedSetting -Entity $h -Name 'ScratchConfig.CurrentScratchLocation'   -ErrorAction SilentlyContinue).Value
    } catch { }
    $isTmpfs   = ("$cur" -match '^/tmp' -or ("$cur" -match 'scratch$' -and "$cfg" -ne "$cur"))
    $isPersist = ("$cur" -match '/vmfs/volumes/|nfs|vsanDatastore' -and "$cur" -notmatch 'tmpfs')
    $status = if ($isTmpfs)              { 'TMPFS (logs lost at reboot)' }
              elseif ($isPersist)        { 'OK (persistent)' }
              elseif (-not $cfg -and -not $cur) { 'UNKNOWN (no settings returned)' }
              else                       { 'REVIEW' }
    [pscustomobject]@{
        Host               = $h.Name
        Cluster            = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
        ConfiguredLocation = if ($cfg) { "$cfg" } else { '(unset)' }
        CurrentLocation    = if ($cur) { "$cur" } else { '(unknown)' }
        Status             = $status
    }
}

$TableFormat = @{
    Status = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'TMPFS') { 'bad' } elseif ("$v" -match 'REVIEW|UNKNOWN|SKIP') { 'warn' } else { '' } }
}
