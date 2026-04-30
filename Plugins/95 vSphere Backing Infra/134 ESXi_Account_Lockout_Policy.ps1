# Start of Settings
$MaxFailures        = 5
$MinUnlockSeconds   = 900
$MinPasswordHistory = 5
$MaxPasswordAgeDays = 90
# End of Settings

$Title          = 'ESXi Account Lockout + Password Policy'
$Header         = '[count] host(s) with weak local-account policy'
$Comments       = "vSCG: Local-account lockout policy hardens against brute-force on root. Security.AccountLockFailures=5, Security.AccountUnlockTime>=900s, Security.PasswordHistory>=5, Security.PasswordMaxDays<=90."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = 'Apply via host profile or per-host Set-AdvancedSetting on the four Security.* settings.'

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $f = (Get-AdvancedSetting -Entity $h -Name 'Security.AccountLockFailures' -ErrorAction SilentlyContinue).Value
    $u = (Get-AdvancedSetting -Entity $h -Name 'Security.AccountUnlockTime'   -ErrorAction SilentlyContinue).Value
    $p = (Get-AdvancedSetting -Entity $h -Name 'Security.PasswordHistory'     -ErrorAction SilentlyContinue).Value
    $m = (Get-AdvancedSetting -Entity $h -Name 'Security.PasswordMaxDays'     -ErrorAction SilentlyContinue).Value
    $issues = @()
    if ([int]$f -le 0 -or [int]$f -gt $MaxFailures) { $issues += "LockFailures=$f (want $MaxFailures)" }
    if ([int]$u -lt $MinUnlockSeconds)              { $issues += "UnlockTime=$u (want >=$MinUnlockSeconds)" }
    if ([int]$p -lt $MinPasswordHistory)            { $issues += "PasswordHistory=$p (want >=$MinPasswordHistory)" }
    if ([int]$m -le 0 -or [int]$m -gt $MaxPasswordAgeDays) { $issues += "PasswordMaxDays=$m (want <=$MaxPasswordAgeDays)" }
    if ($issues.Count -gt 0) {
        [pscustomobject]@{
            Host                = $h.Name
            AccountLockFailures = $f
            AccountUnlockTime   = $u
            PasswordHistory     = $p
            PasswordMaxDays     = $m
            Issues              = ($issues -join '; ')
        }
    }
}
