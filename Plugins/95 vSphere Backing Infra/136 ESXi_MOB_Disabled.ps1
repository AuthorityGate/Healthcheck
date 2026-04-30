# Start of Settings
# End of Settings

$Title          = 'ESXi Managed Object Browser (MOB) Disabled'
$Header         = 'Per-host MOB enable state (every host listed)'
$Comments       = 'vSCG: Config.HostAgent.plugins.solo.enableMob exposes the Managed Object Browser, a JSON/HTML introspection of every ESXi managed object. Useful for support, attack surface in production. Default in 6.7+ is disabled. Every host listed regardless of state.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.1
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Disable on each host: Get-VMHost <name> | Get-AdvancedSetting -Name Config.HostAgent.plugins.solo.enableMob | Set-AdvancedSetting -Value `$false"

if (-not $Global:VCConnected) { return }

$hosts = @(Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Note='Get-VMHost returned no hosts.' }
    return
}

foreach ($h in $hosts) {
    if ($h.ConnectionState -ne 'Connected') {
        [pscustomobject]@{ Host=$h.Name; Cluster=if ($h.Parent) { "$($h.Parent.Name)" } else { '' }; MobEnabled=''; Status='SKIPPED (disconnected)' }
        continue
    }
    $v = (Get-AdvancedSetting -Entity $h -Name 'Config.HostAgent.plugins.solo.enableMob' -ErrorAction SilentlyContinue).Value
    $enabled = [bool]$v
    [pscustomobject]@{
        Host       = $h.Name
        Cluster    = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
        MobEnabled = $enabled
        Status     = if ($enabled) { 'EXPOSED' } else { 'OK' }
        Note       = if ($enabled) { 'MOB exposes managed-object metadata at https://<host>/mob/ - disable in production.' } else { '' }
    }
}

$TableFormat = @{
    MobEnabled = { param($v,$row) if ($v -eq $true) { 'bad' } else { '' } }
    Status     = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -eq 'EXPOSED') { 'bad' } else { 'warn' } }
}
