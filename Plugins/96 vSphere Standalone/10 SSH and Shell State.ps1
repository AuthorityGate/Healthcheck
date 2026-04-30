# Start of Settings
# End of Settings

$Title          = "SSH / ESXi Shell + Lockdown Mode"
$Header         = "[count] host(s) with SSH or ESXi Shell running outside maintenance, or with lockdown disabled"
$Comments       = "vSphere Hardening Guide: SSH and ESXi Shell should be Stopped + Policy=off in production; enabled briefly only for break-glass. Lockdown mode (Normal or Strict) restricts direct host login. KB 1017910 / 1019705."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "Stop SSH / ESXi Shell services and set startup policy to 'Start and stop manually'. Enable lockdown mode 'Normal' (allow DCUI exception list) on all production hosts."

if (-not $Global:VCConnected) { return }

Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h  = $_
    $svc = Get-VMHostService -VMHost $h -ErrorAction SilentlyContinue
    $ssh = $svc | Where-Object { $_.Key -eq 'TSM-SSH' }
    $sh  = $svc | Where-Object { $_.Key -eq 'TSM' }
    $lockdown = $h.ExtensionData.Config.LockdownMode
    $bad = ($ssh.Running) -or ($sh.Running) -or ($lockdown -eq 'lockdownDisabled')
    if ($bad) {
        [pscustomobject]@{
            Host         = $h.Name
            SSHRunning   = [bool]$ssh.Running
            SSHPolicy    = $ssh.Policy
            ShellRunning = [bool]$sh.Running
            ShellPolicy  = $sh.Policy
            Lockdown     = $lockdown
        }
    }
}

$TableFormat = @{
    SSHRunning   = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
    ShellRunning = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
    Lockdown     = { param($v,$row) if ($v -eq 'lockdownDisabled') { 'bad' } else { '' } }
}
