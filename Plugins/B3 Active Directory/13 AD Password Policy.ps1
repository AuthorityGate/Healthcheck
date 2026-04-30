# Start of Settings
# End of Settings

$Title          = "AD Password Policy (Default + Fine-Grained)"
$Header         = "Default Domain Password Policy + every Fine-Grained Password Policy"
$Comments       = "Reads the Default Domain Password Policy and every PSO (Fine-Grained Password Policy) defined in AD. Microsoft / NIST 800-63B baseline: minLen >= 14, no max age, complexity ON for service accounts. Privileged-user PSOs typically tighten this further (24 chars + smartcard-required)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B3 Active Directory"
$Severity       = "P2"
$Recommendation = "Default domain policy minPasswordLength < 12 = compliance gap. MaxPasswordAge > 365 OR < 90 days both warrant review (modern guidance is no expiry + breach detection vs old 60-90 day mandate). Fine-Grained Password Policies should EXIST for privileged groups."

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    [pscustomobject]@{ Note = 'ActiveDirectory PowerShell module not available.' }
    return
}
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

# Build common -Server / -Credential splat from the AD tab's first row.
$_adArgs = @{}
$_adServer = if ($Global:ADServerFqdn) { $Global:ADServerFqdn } elseif ($Global:ADForestFqdn) { $Global:ADForestFqdn } else { $null }
if ($_adServer) { $_adArgs.Server = $_adServer }
if (Test-Path Variable:Global:ADCredential) { $_adArgs.Credential = $Global:ADCredential }

$rows = New-Object System.Collections.ArrayList
try {
    $pol = Get-ADDefaultDomainPasswordPolicy @_adArgs -ErrorAction Stop
    [void]$rows.Add([pscustomobject]@{
        PolicyName       = 'Default Domain Password Policy'
        Precedence       = '(default)'
        MinLength        = $pol.MinPasswordLength
        ComplexityOn     = [bool]$pol.ComplexityEnabled
        MaxAgeDays       = if ($pol.MaxPasswordAge.TotalDays -gt 0) { [int]$pol.MaxPasswordAge.TotalDays } else { 0 }
        MinAgeDays       = [int]$pol.MinPasswordAge.TotalDays
        HistoryCount     = $pol.PasswordHistoryCount
        LockoutThreshold = $pol.LockoutThreshold
        LockoutDuration  = if ($pol.LockoutDuration) { [int]$pol.LockoutDuration.TotalMinutes } else { 0 }
        ReversibleEnc    = [bool]$pol.ReversibleEncryptionEnabled
        AppliesTo        = '(domain)'
    })
} catch { }

try {
    $psos = @(Get-ADFineGrainedPasswordPolicy -Filter * @_adArgs -ErrorAction Stop)
    foreach ($pso in $psos) {
        [void]$rows.Add([pscustomobject]@{
            PolicyName       = $pso.Name
            Precedence       = $pso.Precedence
            MinLength        = $pso.MinPasswordLength
            ComplexityOn     = [bool]$pso.ComplexityEnabled
            MaxAgeDays       = if ($pso.MaxPasswordAge.TotalDays -gt 0) { [int]$pso.MaxPasswordAge.TotalDays } else { 0 }
            MinAgeDays       = [int]$pso.MinPasswordAge.TotalDays
            HistoryCount     = $pso.PasswordHistoryCount
            LockoutThreshold = $pso.LockoutThreshold
            LockoutDuration  = if ($pso.LockoutDuration) { [int]$pso.LockoutDuration.TotalMinutes } else { 0 }
            ReversibleEnc    = [bool]$pso.ReversibleEncryptionEnabled
            AppliesTo        = ($pso.AppliesTo -join ', ')
        })
    }
} catch { }

if ($rows.Count -eq 0) {
    [pscustomobject]@{ Note = 'Could not read password policies. Confirm AD module + RSAT installed.' }
    return
}
$rows

$TableFormat = @{
    MinLength = { param($v,$row) if ([int]"$v" -lt 12) { 'bad' } elseif ([int]"$v" -lt 14) { 'warn' } else { 'ok' } }
    ComplexityOn = { param($v,$row) if ($v -eq $true) { 'ok' } else { 'warn' } }
    ReversibleEnc = { param($v,$row) if ($v -eq $true) { 'bad' } else { 'ok' } }
    LockoutThreshold = { param($v,$row) if ([int]"$v" -gt 10 -or [int]"$v" -eq 0) { 'warn' } else { 'ok' } }
}
