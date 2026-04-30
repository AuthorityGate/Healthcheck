# Start of Settings
# End of Settings

$Title          = "AD LAPS Deployment Coverage"
$Header         = "[count] computer(s) reporting LAPS-managed local-admin password"
$Comments       = "Counts machines whose AD computer object has the ms-Mcs-AdmPwdExpirationTime attribute populated (legacy LAPS) OR msLAPS-PasswordExpirationTime (Windows LAPS, the 2023 successor). Ratio of LAPS-managed to total = local-admin-credential rotation coverage. Without LAPS, every machine has the same baked-in local Administrator password = lateral-movement gold."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = "B3 Active Directory"
$Severity       = "P1"
$Recommendation = "Below 90% LAPS coverage = compliance gap on every modern security baseline. Migrate from legacy LAPS to Windows LAPS (built-in to Win11 + Server 2019+); the modern attribute is msLAPS-PasswordExpirationTime."

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

# Schema-attribute probe FIRST so we only query attributes that exist.
# On forests where one of the LAPS schema extensions wasn't applied,
# Get-ADComputer -Properties 'ms-Mcs-AdmPwdExpirationTime' would error
# 'One or more properties are invalid' and we'd lose the row entirely.
$schemaNc = $null
try { $schemaNc = (Get-ADRootDSE @_adArgs -ErrorAction SilentlyContinue).schemaNamingContext } catch { }
$hasLegacyAttr  = $false
$hasWindowsAttr = $false
if ($schemaNc) {
    try { $hasLegacyAttr  = [bool](Get-ADObject -Filter "lDAPDisplayName -eq 'ms-Mcs-AdmPwd'"  -SearchBase $schemaNc @_adArgs -ErrorAction SilentlyContinue) } catch { }
    try { $hasWindowsAttr = [bool](Get-ADObject -Filter "lDAPDisplayName -eq 'msLAPS-Password'" -SearchBase $schemaNc @_adArgs -ErrorAction SilentlyContinue) } catch { }
}

try {
    $totalCmp = @(Get-ADComputer -Filter { Enabled -eq $true } @_adArgs -ErrorAction Stop).Count
    $legacyLaps = 0
    if ($hasLegacyAttr) {
        $legacyLaps = @(Get-ADComputer -Filter { Enabled -eq $true } -Properties 'ms-Mcs-AdmPwdExpirationTime' @_adArgs -ErrorAction Stop |
                        Where-Object { $_.'ms-Mcs-AdmPwdExpirationTime' -gt 0 }).Count
    }
    $windowsLaps = 0
    if ($hasWindowsAttr) {
        $windowsLaps = @(Get-ADComputer -Filter { Enabled -eq $true } -Properties 'msLAPS-PasswordExpirationTime' @_adArgs -ErrorAction Stop |
                         Where-Object { $_.'msLAPS-PasswordExpirationTime' -gt 0 }).Count
    }
} catch {
    [pscustomobject]@{ Note = "AD query failed: $($_.Exception.Message)" }
    return
}

$totalCovered = ($legacyLaps + $windowsLaps)
$pct = if ($totalCmp -gt 0) { [math]::Round(($totalCovered / $totalCmp) * 100, 1) } else { 0 }

[pscustomobject]@{
    EnabledComputers      = $totalCmp
    LegacyLapsCovered     = $legacyLaps
    WindowsLapsCovered    = $windowsLaps
    TotalLapsCovered      = $totalCovered
    PctLapsCovered        = $pct
    SchemaHasLegacyAttr   = $hasLegacyAttr
    SchemaHasWindowsAttr  = $hasWindowsAttr
}

$TableFormat = @{
    PctLapsCovered = { param($v,$row) if ([double]"$v" -lt 50) { 'bad' } elseif ([double]"$v" -lt 90) { 'warn' } else { 'ok' } }
}
