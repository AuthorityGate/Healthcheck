# Start of Settings
# Users not logged on for this many days are flagged as stale.
$StaleDays = 90
# Cap rows to keep the report readable - large directories can have thousands.
$MaxRows = 200
# End of Settings

$Title          = 'AD Stale User Accounts'
$Header         = "Users with no recent logon (LastLogonTimestamp older than $StaleDays days)"
$Comments       = "Stale accounts are a major attack surface (lateral movement, password spray). LastLogonTimestamp replicates every ~14 days, so values may be up to 14 days behind reality. Disabled accounts are listed separately as low-risk."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = 'B3 Active Directory'
$Severity       = 'P2'
$Recommendation = "Disable accounts inactive > 90 days and move to a 'Stale' OU; delete after a documented hold period (e.g., 180 days). Establish an automated lifecycle process - manual cleanup never scales."

if (-not (Test-Path Variable:Global:ADForestFqdn) -or -not $Global:ADForestFqdn) { return }
try { Import-Module ActiveDirectory -ErrorAction Stop } catch { return }

$adArgs = @{ Server = $(if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { $Global:ADForestFqdn }) }
if (Test-Path Variable:Global:ADCredential) { $adArgs.Credential = $Global:ADCredential }

try {
    $forest = Get-ADForest -Identity $Global:ADForestFqdn @adArgs -ErrorAction Stop
    $cutoff = (Get-Date).AddDays(-$StaleDays).ToFileTime()
    foreach ($d in $forest.Domains) {
        $u = @{ Filter = "(LastLogonTimestamp -lt $cutoff -or LastLogonTimestamp -notlike '*') -and Enabled -eq `$true"; Properties=@('LastLogonTimestamp','Enabled','PasswordLastSet','whenCreated','Description'); Server=$d; ErrorAction='SilentlyContinue' }
        if (Test-Path Variable:Global:ADCredential) { $u.Credential = $Global:ADCredential }
        $rows = @(Get-ADUser @u | Sort-Object LastLogonTimestamp | Select-Object -First $MaxRows)
        $totalStale = $rows.Count
        if ($totalStale -eq 0) {
            [pscustomobject]@{ Domain=$d; SamAccountName=''; LastLogon=''; PasswordLastSet=''; Status="OK (0 stale users in $d)" }
            continue
        }
        foreach ($row in $rows) {
            $lastLogon = if ($row.LastLogonTimestamp) { [datetime]::FromFileTime([long]$row.LastLogonTimestamp) } else { $null }
            $daysSince = if ($lastLogon) { [int]((Get-Date) - $lastLogon).TotalDays } else { 'never' }
            [pscustomobject]@{
                Domain          = $d
                SamAccountName  = $row.SamAccountName
                Enabled         = $row.Enabled
                LastLogon       = if ($lastLogon) { $lastLogon.ToString('yyyy-MM-dd') } else { 'never' }
                DaysSinceLogon  = $daysSince
                PasswordLastSet = if ($row.PasswordLastSet) { $row.PasswordLastSet.ToString('yyyy-MM-dd') } else { '' }
                WhenCreated     = if ($row.whenCreated) { $row.whenCreated.ToString('yyyy-MM-dd') } else { '' }
                Description     = "$($row.Description)"
                Status          = if ("$daysSince" -eq 'never') { 'NEVER LOGGED ON' } elseif ([int]$daysSince -gt 365) { "OLD (>1 yr)" } else { "STALE ($daysSince d)" }
            }
        }
        if ($totalStale -ge $MaxRows) {
            [pscustomobject]@{ Domain=$d; Status="TRUNCATED at $MaxRows rows - more stale users exist" }
        }
    }
} catch {
    [pscustomobject]@{ Domain='ERROR'; Status=$_.Exception.Message }
}

$TableFormat = @{
    Enabled = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
    Status  = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'NEVER|OLD|TRUNC') { 'warn' } elseif ("$v" -match 'STALE') { 'warn' } else { '' } }
}
