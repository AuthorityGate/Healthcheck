# Start of Settings
# Recommended idle/availability timeouts (seconds). Zero means "never auto-disable",
# which is exactly what you don't want.
$ShellTimeout            = 600
$ShellInteractiveTimeout = 600
$DcuiTimeout             = 600
# End of Settings

$Title          = 'ESXi Shell + DCUI Timeouts'
$Header         = '[count] host(s) with ESXi Shell, SSH, or DCUI timeouts not set'
$Comments       = 'vSCG: Shell-related advanced settings should be set so that an enabled shell auto-disables and idle sessions auto-logout. Zero = disabled = never auto-disconnects = bad.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Set on each host: UserVars.ESXiShellTimeOut=600, UserVars.ESXiShellInteractiveTimeOut=600, UserVars.DcuiTimeOut=600. Apply via host profile for consistency."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $sh   = (Get-AdvancedSetting -Entity $h -Name 'UserVars.ESXiShellTimeOut'            -ErrorAction SilentlyContinue).Value
    $shi  = (Get-AdvancedSetting -Entity $h -Name 'UserVars.ESXiShellInteractiveTimeOut' -ErrorAction SilentlyContinue).Value
    $dcui = (Get-AdvancedSetting -Entity $h -Name 'UserVars.DcuiTimeOut'                 -ErrorAction SilentlyContinue).Value
    $bad = ([int]$sh -le 0) -or ([int]$shi -le 0) -or ([int]$dcui -le 0)
    if ($bad) {
        [pscustomobject]@{
            Host                       = $h.Name
            ESXiShellTimeOut           = $sh
            ESXiShellInteractiveTimeOut= $shi
            DcuiTimeOut                = $dcui
            Recommended                = "$ShellTimeout / $ShellInteractiveTimeout / $DcuiTimeout"
        }
    }
}

$TableFormat = @{
    ESXiShellTimeOut            = { param($v,$row) if ([int]$v -le 0) { 'bad' } else { '' } }
    ESXiShellInteractiveTimeOut = { param($v,$row) if ([int]$v -le 0) { 'bad' } else { '' } }
    DcuiTimeOut                 = { param($v,$row) if ([int]$v -le 0) { 'bad' } else { '' } }
}
