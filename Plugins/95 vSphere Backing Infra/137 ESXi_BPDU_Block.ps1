# Start of Settings
# End of Settings

$Title          = 'ESXi Block Guest BPDUs'
$Header         = 'Per-host Net.BlockGuestBPDU value (every host listed)'
$Comments       = 'KB 2034605: Net.BlockGuestBPDU=1 prevents a compromised VM from sending Bridge Protocol Data Units that could trick the physical switch into changing topology (BPDU Guard bypass). Lists every host regardless of value so the audit is verifiable.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.1
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Set on each host: Get-VMHost <name> | Get-AdvancedSetting -Name Net.BlockGuestBPDU | Set-AdvancedSetting -Value 1"

if (-not $Global:VCConnected) { return }

$hosts = @(Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Note='Get-VMHost returned no hosts.' }
    return
}

foreach ($h in $hosts) {
    if ($h.ConnectionState -ne 'Connected') {
        [pscustomobject]@{ Host=$h.Name; Cluster=if ($h.Parent) { "$($h.Parent.Name)" } else { '' }; BlockGuestBPDU=''; Recommended=1; Status='SKIPPED (disconnected)' }
        continue
    }
    $v = (Get-AdvancedSetting -Entity $h -Name 'Net.BlockGuestBPDU' -ErrorAction SilentlyContinue).Value
    $iv = if ($null -eq $v) { -1 } else { [int]$v }
    $status = if ($iv -eq 1) { 'OK' }
              elseif ($iv -eq 0) { 'BLOCK OFF' }
              elseif ($iv -lt 0) { 'NOT QUERIED' }
              else { "UNEXPECTED ($iv)" }
    [pscustomobject]@{
        Host           = $h.Name
        Cluster        = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
        BlockGuestBPDU = if ($iv -lt 0) { '(unset)' } else { $iv }
        Recommended    = 1
        Status         = $status
    }
}

$TableFormat = @{
    BlockGuestBPDU = { param($v,$row) if ("$v" -eq '1') { 'ok' } elseif ("$v" -eq '0' -or "$v" -eq '(unset)') { 'bad' } else { 'warn' } }
    Status         = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -match 'OFF|UNEXPECTED|NOT QUERIED') { 'bad' } else { 'warn' } }
}
