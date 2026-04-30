# Start of Settings
$WarnDays = 180
$BadDays  = 365
# End of Settings

$Title          = "AD KRBTGT Password Age"
$Header         = "Per-domain KRBTGT account password age"
$Comments       = "KRBTGT is the account that signs every Kerberos ticket. Microsoft strongly recommends rotating its password every 90-180 days; Mimikatz and golden-ticket attacks rely on a stale KRBTGT hash. Plugin reports the age across each domain in the forest plus any RODC's KrbTgt_<rodc> sibling account."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B3 Active Directory"
$Severity       = "P1"
$Recommendation = "Rotate KRBTGT TWICE in succession (with at least 10h gap between rotations) every 6 months at minimum. Use Microsoft's official New-KrbtgtKeys.ps1 script. Test in non-prod first - the rotation invalidates all current Kerberos tickets and causes a brief auth pause."

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    [pscustomobject]@{ Note = 'ActiveDirectory PowerShell module not available.' }
    return
}
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

# Build common -Credential splat from the AD tab's first row. Per-domain
# loop below sets -Server explicitly to each domain FQDN.
$_adCredArgs = @{}
if (Test-Path Variable:Global:ADCredential) { $_adCredArgs.Credential = $Global:ADCredential }

# Forest discovery: prefer the operator-supplied DC; fall back to runner
# domain context which usually fails on a non-domain-joined runner.
$_forestServerArgs = @{}
$_forestSeed = if ($Global:ADServerFqdn) { $Global:ADServerFqdn } elseif ($Global:ADForestFqdn) { $Global:ADForestFqdn } else { $null }
if ($_forestSeed) { $_forestServerArgs.Server = $_forestSeed }

try { $domains = @((Get-ADForest @_forestServerArgs @_adCredArgs).Domains) } catch { $domains = @($env:USERDNSDOMAIN) }
foreach ($d in $domains) {
    if (-not $d) { continue }
    try {
        $accts = @(Get-ADUser -Server $d -Filter "samAccountName -like 'krbtgt*'" -Properties PasswordLastSet @_adCredArgs -ErrorAction Stop)
        foreach ($a in $accts) {
            $age = if ($a.PasswordLastSet) { [int]((Get-Date) - $a.PasswordLastSet).TotalDays } else { $null }
            [pscustomobject]@{
                Domain         = $d
                Account        = $a.SamAccountName
                PasswordLastSet = if ($a.PasswordLastSet) { $a.PasswordLastSet.ToString('yyyy-MM-dd') } else { '' }
                AgeDays        = $age
                Status         = if ($age -ge $BadDays) { 'OVERDUE' } elseif ($age -ge $WarnDays) { 'AGING' } else { 'OK' }
            }
        }
    } catch {
        [pscustomobject]@{ Domain=$d; Account=''; PasswordLastSet=''; AgeDays=''; Status="ERROR: $($_.Exception.Message)" }
    }
}

$TableFormat = @{
    Status  = { param($v,$row) if ($v -eq 'OVERDUE') { 'bad' } elseif ($v -eq 'AGING') { 'warn' } elseif ($v -eq 'OK') { 'ok' } else { '' } }
    AgeDays = { param($v,$row) if ([int]"$v" -ge $BadDays) { 'bad' } elseif ([int]"$v" -ge $WarnDays) { 'warn' } else { '' } }
}
