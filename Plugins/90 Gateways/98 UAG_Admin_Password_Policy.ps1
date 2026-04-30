# Start of Settings
# End of Settings

$Title          = 'UAG Admin Password Policy'
$Header         = 'Admin policy + password rotation'
$Comments       = "UAG ships with 'admin' / configurable password. Rotation policy + complexity enforcement is admin-set. Endpoint location varies between UAG builds; this plugin probes multiple known paths and surfaces whatever the appliance exposes."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '90 Gateways'
$Severity       = 'P2'
$Recommendation = 'Set min length 14, complexity on, password expiration 90 days. Rotate annually at minimum.'

if (-not (Get-UAGRestSession)) { return }

# Probe candidate paths - older UAG (3.x), newer UAG (2306+), and the
# Horizon-style alt naming. First non-null wins.
$pol = $null
foreach ($p in @(
    '/config/system/adminpolicy',
    '/config/adminpolicy',
    '/config/admin-policy',
    '/config/system/adminPasswordPolicy'
)) {
    try { $pol = Invoke-UAGRest -Path $p; if ($pol) { break } } catch { }
}
if (-not $pol) {
    [pscustomobject]@{
        Setting = '(endpoint not exposed)'
        Value   = ''
        Note    = 'No /config/*adminpolicy endpoint answered on this UAG build. Verify policy manually via the UAG admin UI.'
    }
    return
}

# Multiple field-name variants depending on UAG version
function Get-V { param($Obj,[string[]]$Names) foreach ($n in $Names) { if ($Obj.PSObject.Properties[$n] -and $null -ne $Obj.$n) { return $Obj.$n } } ; return $null }

[pscustomobject]@{
    MinPasswordLength      = (Get-V $pol @('minPasswordLength','minLength','min_password_length'))
    MinNumberOfDigits      = (Get-V $pol @('minNumberOfDigits','minDigits','min_digits'))
    MinNumberOfSpecial     = (Get-V $pol @('minNumberOfSpecialCharacters','minSpecialCharacters','min_special_chars'))
    MaxFailedAttempts      = (Get-V $pol @('maxFailedLogins','maxFailedAttempts','max_failed_attempts'))
    PasswordExpirationDays = (Get-V $pol @('passwordExpiryInDays','passwordExpirationDays','password_expiry_days'))
    LockoutMinutes         = (Get-V $pol @('lockoutMinutes','lockoutTime','account_lockout_minutes'))
    PasswordHistory        = (Get-V $pol @('passwordHistory','passwordHistoryCount','password_history_count'))
}

$TableFormat = @{
    MinPasswordLength = { param($v,$row) if ([int]"$v" -lt 14) { 'warn' } elseif ([int]"$v" -ge 14) { 'ok' } else { '' } }
    PasswordExpirationDays = { param($v,$row) if ([int]"$v" -gt 365 -or [int]"$v" -eq 0) { 'warn' } else { 'ok' } }
}
