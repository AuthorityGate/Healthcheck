# Start of Settings
# Advanced settings whose deviation from default is worth flagging.
$Watchlist = @(
    @{ Name='UserVars.SuppressShellWarning';      Default=0; Severity='P3'; Note='Shell warning suppression - hides ESXi shell-enabled warning' }
    @{ Name='UserVars.ESXiShellTimeOut';          Default=0; Severity='P3'; Note='Shell session timeout in seconds (0 = none = bad)' }
    @{ Name='UserVars.ESXiShellInteractiveTimeOut';Default=0; Severity='P3'; Note='Idle shell timeout (0 = none)' }
    @{ Name='Security.AccountUnlockTime';         Default=900; Severity='P3'; Note='Lockout duration for failed admin login' }
    @{ Name='Security.AccountLockFailures';       Default=5; Severity='P3'; Note='Failed-login threshold' }
    @{ Name='Security.PasswordHistory';           Default=5; Severity='P3'; Note='Password history depth' }
    @{ Name='Security.PasswordQualityControl';    Default='retry=3 min=disabled,disabled,disabled,7,7'; Severity='P3'; Note='Password complexity rule' }
    @{ Name='Net.BlockGuestBPDU';                 Default=1; Severity='P2'; Note='Block guest-injected BPDUs' }
    @{ Name='DCUI.Access';                        Default='root'; Severity='P3'; Note='DCUI break-glass account list' }
    @{ Name='Misc.HostAgentUpdateLevel';          Default=3; Severity='P3'; Note='Host Agent update level' }
)
# End of Settings

$Title          = 'ESXi Advanced Settings Drift'
$Header         = "[count] advanced setting deviation(s) across hosts"
$Comments       = "Audits a watchlist of security-relevant advanced settings vs documented defaults. Drift = either intentional (document the why) or unintentional (fix it)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P3'
$Recommendation = "For each row, justify the deviation OR set the value back to default. Configure at host profile / vLCM image so future re-builds inherit."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue)) {
    if ($h.ConnectionState -ne 'Connected') { continue }
    foreach ($w in $Watchlist) {
        $adv = Get-AdvancedSetting -Entity $h -Name $w.Name -ErrorAction SilentlyContinue
        if (-not $adv) { continue }
        $current = $adv.Value
        # Allow string OR numeric compare
        $deviates = if ($w.Default -is [string]) { "$current" -ne "$($w.Default)" } else { $current -ne $w.Default }
        if ($deviates) {
            [pscustomobject]@{
                Host    = $h.Name
                Cluster = if ($h.Parent) { $h.Parent.Name } else { '' }
                Setting = $w.Name
                Current = "$current"
                Default = "$($w.Default)"
                Severity= $w.Severity
                Note    = $w.Note
            }
        }
    }
}

$TableFormat = @{
    Severity = { param($v,$row) if ($v -eq 'P1') { 'bad' } elseif ($v -eq 'P2') { 'warn' } else { '' } }
}
