# Start of Settings
$StaleDays = 90
$MaxRendered = 1000
# End of Settings

$Title          = "AD Stale Computer Accounts"
$Header         = "[count] computer account(s) with no logon in $StaleDays+ days"
$Comments       = "Computers in AD that have not authenticated in 90+ days. Common with Horizon: deleted instant-clone parent VMs, decommissioned RDSH hosts, retired user laptops. Stale accounts inflate the directory, complicate group-policy targeting, and can be reused by an attacker who finds an old machine cert."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B3 Active Directory"
$Severity       = "P3"
$Recommendation = "Disable then delete in two phases (90 days disabled before delete) so any legitimate seasonal use surfaces. Horizon's instant-clone OUs should be excluded - they recycle naturally. Consider AD Cleanup tools (e.g., AD Tidy) for ongoing automation."

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

$cutoff = (Get-Date).AddDays(-$StaleDays)
try {
    $stale = @(Get-ADComputer -Filter { LastLogonTimeStamp -lt $cutoff } `
                              -Properties LastLogonTimeStamp, PasswordLastSet, OperatingSystem, Enabled @_adArgs -ErrorAction Stop |
        Sort-Object LastLogonTimeStamp |
        Select-Object -First $MaxRendered)
} catch {
    [pscustomobject]@{ Note = "AD query failed: $($_.Exception.Message)" }
    return
}

if ($stale.Count -eq 0) {
    [pscustomobject]@{ Note = "No computer accounts older than $StaleDays days." }
    return
}

foreach ($c in $stale) {
    $lastLogon = if ($c.LastLogonTimeStamp) { [datetime]::FromFileTime($c.LastLogonTimeStamp) } else { $null }
    [pscustomobject]@{
        Computer        = $c.Name
        OS              = $c.OperatingSystem
        Enabled         = [bool]$c.Enabled
        LastLogon       = if ($lastLogon) { $lastLogon.ToString('yyyy-MM-dd') } else { '(never)' }
        AgeDays         = if ($lastLogon) { [int]((Get-Date) - $lastLogon).TotalDays } else { 9999 }
        OU              = ($c.DistinguishedName -replace '^CN=[^,]+,','')
    }
}

$TableFormat = @{
    AgeDays = { param($v,$row) if ([int]"$v" -gt 365) { 'bad' } elseif ([int]"$v" -gt 180) { 'warn' } else { '' } }
    Enabled = { param($v,$row) if ($v -eq $true) { 'warn' } elseif ($v -eq $false) { 'ok' } else { '' } }
}
