# Start of Settings
# End of Settings

$Title          = 'ESXi Lockdown Exception List Audit'
$Header         = 'Per-host lockdown mode + exception list count (every host listed)'
$Comments       = "Lockdown Mode (Strict / Normal) restricts host management to vCenter. The exception list explicitly allows specific accounts to bypass lockdown. Over-broad exception list defeats the security control. Lists every host so operators can verify the audit ran even when no exceptions exist."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Exception list should be empty (Strict mode) OR contain only documented break-glass accounts. Each exception requires written justification + audit trail."

if (-not $Global:VCConnected) { return }

$hosts = @(Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Note='Get-VMHost returned no hosts.' }
    return
}

foreach ($h in $hosts) {
    $mode = ''
    $list = @()
    $err  = $null
    if ($h.ConnectionState -ne 'Connected') {
        [pscustomobject]@{
            Host=$h.Name; Cluster=if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
            LockdownMode='(disconnected)'; ExceptionCount=''; ExceptionUsers=''; Status='SKIPPED (host disconnected)'
        }
        continue
    }
    try {
        $mode = "$($h.ExtensionData.Config.LockdownMode)"
        $hostAcc = Get-View -Id $h.ExtensionData.ConfigManager.HostAccessManager -ErrorAction Stop
        $list = @($hostAcc.QueryLockdownExceptions())
    } catch { $err = $_.Exception.Message }

    $status = if ($err) { "ERR: $err" }
              elseif ($mode -eq 'lockdownDisabled') { 'LOCKDOWN OFF' }
              elseif (@($list).Count -eq 0) { "OK ($mode, no exceptions)" }
              else { "REVIEW ($($list.Count) exception(s))" }

    [pscustomobject]@{
        Host           = $h.Name
        Cluster        = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
        LockdownMode   = $mode
        ExceptionCount = @($list).Count
        ExceptionUsers = if (@($list).Count -gt 0) { ($list -join ', ') } else { '(none)' }
        Status         = $status
    }
}

$TableFormat = @{
    LockdownMode   = { param($v,$row) if ("$v" -eq 'lockdownDisabled') { 'bad' } elseif ("$v" -eq 'lockdownNormal') { 'warn' } elseif ("$v" -eq 'lockdownStrict') { 'ok' } else { '' } }
    ExceptionCount = { param($v,$row) if ("$v" -match '^\d+$' -and [int]"$v" -gt 0) { 'warn' } else { '' } }
    Status         = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'OFF|ERR') { 'bad' } elseif ("$v" -match 'REVIEW|SKIP') { 'warn' } else { '' } }
}
