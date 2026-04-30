# Start of Settings
# End of Settings

$Title          = 'AD Account Lockout + Password Policy Detail'
$Header         = 'Default-domain lockout thresholds + every fine-grained policy'
$Comments       = "Default Domain Policy lockout settings + Fine-Grained Password Policy (FGPP) inventory. NIST SP 800-63B / CIS Benchmark recommend: lockout threshold 5-10, observation window 15+ minutes, complexity enforced, history >= 24."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = 'B3 Active Directory'
$Severity       = 'P2'
$Recommendation = "Set LockoutThreshold to 5-10. ObservationWindow + Duration both >= 15 minutes (CIS 1.1). Enforce password history >= 24, complexity = true, MaxAge <= 365."

if (-not (Test-Path Variable:Global:ADForestFqdn) -or -not $Global:ADForestFqdn) { return }
try { Import-Module ActiveDirectory -ErrorAction Stop } catch { return }

$adArgs = @{ Server = $(if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { $Global:ADForestFqdn }) }
if (Test-Path Variable:Global:ADCredential) { $adArgs.Credential = $Global:ADCredential }

try {
    $forest = Get-ADForest -Identity $Global:ADForestFqdn @adArgs -ErrorAction Stop
    foreach ($d in $forest.Domains) {
        $a = @{ Identity = $d; Server = $d; ErrorAction = 'SilentlyContinue' }
        if (Test-Path Variable:Global:ADCredential) { $a.Credential = $Global:ADCredential }
        $pol = Get-ADDefaultDomainPasswordPolicy @a
        if ($pol) {
            $thr = [int]$pol.LockoutThreshold
            $status = if ($thr -eq 0) { 'BAD (lockout disabled)' }
                      elseif ($thr -gt 10) { 'WARN (threshold > 10)' }
                      elseif ($thr -lt 3) { 'WARN (threshold too low - DoS risk)' }
                      else { 'OK' }
            [pscustomobject]@{
                Scope               = "$d (Default)"
                LockoutThreshold    = $thr
                LockoutDurationMin  = if ($pol.LockoutDuration) { [int]$pol.LockoutDuration.TotalMinutes } else { '' }
                ObservationWindowMin= if ($pol.LockoutObservationWindow) { [int]$pol.LockoutObservationWindow.TotalMinutes } else { '' }
                MinPasswordLength   = $pol.MinPasswordLength
                ComplexityEnabled   = $pol.ComplexityEnabled
                MaxPasswordAgeDays  = if ($pol.MaxPasswordAge) { [int]$pol.MaxPasswordAge.TotalDays } else { '' }
                MinPasswordAgeDays  = if ($pol.MinPasswordAge) { [int]$pol.MinPasswordAge.TotalDays } else { '' }
                PasswordHistory     = $pol.PasswordHistoryCount
                ReversibleEncryption= $pol.ReversibleEncryptionEnabled
                Status              = $status
            }
        }

        # Fine-Grained Password Policies
        $fgppArgs = @{ Filter='*'; Server=$d; ErrorAction='SilentlyContinue' }
        if (Test-Path Variable:Global:ADCredential) { $fgppArgs.Credential = $Global:ADCredential }
        $fgpps = @(Get-ADFineGrainedPasswordPolicy @fgppArgs)
        foreach ($f in $fgpps) {
            [pscustomobject]@{
                Scope               = "$d / FGPP: $($f.Name) (precedence $($f.Precedence))"
                LockoutThreshold    = $f.LockoutThreshold
                LockoutDurationMin  = if ($f.LockoutDuration) { [int]$f.LockoutDuration.TotalMinutes } else { '' }
                ObservationWindowMin= if ($f.LockoutObservationWindow) { [int]$f.LockoutObservationWindow.TotalMinutes } else { '' }
                MinPasswordLength   = $f.MinPasswordLength
                ComplexityEnabled   = $f.ComplexityEnabled
                MaxPasswordAgeDays  = if ($f.MaxPasswordAge) { [int]$f.MaxPasswordAge.TotalDays } else { '' }
                MinPasswordAgeDays  = if ($f.MinPasswordAge) { [int]$f.MinPasswordAge.TotalDays } else { '' }
                PasswordHistory     = $f.PasswordHistoryCount
                ReversibleEncryption= $f.ReversibleEncryptionEnabled
                Status              = if ([int]$f.LockoutThreshold -eq 0) { 'BAD (lockout disabled)' } else { 'FGPP' }
            }
        }
    }
} catch {
    [pscustomobject]@{ Scope='ERROR'; Status=$_.Exception.Message }
}

$TableFormat = @{
    LockoutThreshold = { param($v,$row) if ("$v" -eq '0') { 'bad' } elseif ([int]"$v" -gt 10) { 'warn' } else { '' } }
    PasswordHistory  = { param($v,$row) if ([int]"$v" -lt 24) { 'warn' } else { '' } }
    ComplexityEnabled = { param($v,$row) if ($v -eq $false) { 'bad' } else { '' } }
    ReversibleEncryption = { param($v,$row) if ($v -eq $true) { 'bad' } else { '' } }
    Status           = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -match 'BAD') { 'bad' } elseif ("$v" -match 'WARN') { 'warn' } else { '' } }
}
