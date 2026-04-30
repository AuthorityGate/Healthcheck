# Start of Settings
# End of Settings

$Title          = 'ESXi Memory Page-Sharing Salt'
$Header         = 'Per-host Mem.ShareForceSalting value (every host listed)'
$Comments       = 'KB 2097593: Mem.ShareForceSalting=2 enforces per-VM salt for memory page sharing, preventing cross-VM TPS-based memory disclosure attacks. Default in 6.0+ is 2. Lists every host regardless of value for audit verification.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.1
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Set on each host: Get-VMHost <name> | Get-AdvancedSetting -Name Mem.ShareForceSalting | Set-AdvancedSetting -Value 2"

if (-not $Global:VCConnected) { return }

$hosts = @(Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Note='Get-VMHost returned no hosts.' }
    return
}

foreach ($h in $hosts) {
    if ($h.ConnectionState -ne 'Connected') {
        [pscustomobject]@{ Host=$h.Name; Cluster=if ($h.Parent) { "$($h.Parent.Name)" } else { '' }; ShareForceSalting=''; Recommended=2; Status='SKIPPED (disconnected)' }
        continue
    }
    $v = (Get-AdvancedSetting -Entity $h -Name 'Mem.ShareForceSalting' -ErrorAction SilentlyContinue).Value
    $iv = if ($null -eq $v) { -1 } else { [int]$v }
    $status = switch ($iv) {
        2  { 'OK (mode 2 = enforced)' }
        1  { 'WEAK (mode 1 = optional)' }
        0  { 'BAD (mode 0 = no salting)' }
        -1 { 'NOT QUERIED' }
        default { "UNEXPECTED ($iv)" }
    }
    [pscustomobject]@{
        Host              = $h.Name
        Cluster           = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
        ShareForceSalting = if ($iv -lt 0) { '(unset)' } else { $iv }
        Recommended       = 2
        Status            = $status
    }
}

$TableFormat = @{
    ShareForceSalting = { param($v,$row) if ("$v" -eq '2') { 'ok' } elseif ("$v" -eq '0') { 'bad' } else { 'warn' } }
    Status            = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'BAD|UNEXPECTED|NOT') { 'bad' } else { 'warn' } }
}
