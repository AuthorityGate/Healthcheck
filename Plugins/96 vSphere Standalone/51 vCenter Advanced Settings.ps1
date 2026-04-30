# Start of Settings
# Advanced settings to surface. Only the security / operationally-meaningful
# ones - the full Get-AdvancedSetting list is hundreds of rows of noise.
$WatchedSettings = @(
    # Audit / event retention
    'event.maxAgeEnabled', 'event.maxAge',
    'task.maxAgeEnabled', 'task.maxAge',
    # Session / inactivity
    'config.vpxd.sso.solutionUser.lifetime',
    'config.vpxd.solutionUser.maxAge',
    # Logging
    'config.log.level',
    'config.log.maxFileNum',
    'config.log.maxFileSize',
    # Auth lockout (vCenter-side)
    'config.vpxd.security.passwordExpirationInterval',
    # SDDC mgmt
    'config.vpxd.locale',
    'config.vpxd.network.proxy.url',
    # Service Control
    'config.vpxd.shutdownDelaySeconds',
    'config.vpxd.taskCompletionTimeout',
    # vCenter HA / linked mode awareness
    'config.vpxd.linkedMode',
    # Certificate management
    'vpxd.certmgmt.mode'
)
# End of Settings

$Title          = 'vCenter Advanced Settings (Security + Operational)'
$Header         = 'Selected vCenter advanced settings (every watched key listed)'
$Comments       = "Pulls Get-AdvancedSetting -Entity <vCenter> for the security and operationally-meaningful keys. Rather than dump hundreds of low-value settings, this plugin lists a curated set: event/task retention, session lifetime, log level, password expiry, certificate management mode, locale, proxy. Each row is an actual current value; verify against the customer's documented standard."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'Info'
$Recommendation = "Common audit defaults to verify: event.maxAge >= 180 (days), task.maxAge >= 180, config.log.level = info or warning (not verbose in production), vpxd.certmgmt.mode = vmca (default; thumbprint = legacy). Settings the customer has explicitly tuned should match their compliance regime."

if (-not $Global:VCConnected) { return }
$vc = $global:DefaultVIServer
if (-not $vc) {
    [pscustomobject]@{ Note = 'No vCenter connected.' }
    return
}

foreach ($key in $WatchedSettings) {
    $setting = Get-AdvancedSetting -Entity $vc -Name $key -ErrorAction SilentlyContinue
    if ($setting) {
        [pscustomobject]@{
            Setting = "$key"
            Value   = "$($setting.Value)"
            Type    = if ($setting.Type) { "$($setting.Type)" } else { '' }
            Status  = 'PRESENT'
        }
    } else {
        [pscustomobject]@{
            Setting = "$key"
            Value   = '(not set)'
            Type    = ''
            Status  = 'DEFAULT (not customized)'
        }
    }
}

$TableFormat = @{
    Status = { param($v,$row) if ("$v" -eq 'PRESENT') { 'ok' } else { '' } }
    Value  = { param($v,$row)
        if ("$($row.Setting)" -eq 'config.log.level' -and "$v" -match 'verbose|trivia') { 'warn' }
        elseif ("$($row.Setting)" -match 'maxAgeEnabled' -and "$v" -eq 'False') { 'warn' }
        else { '' }
    }
}
