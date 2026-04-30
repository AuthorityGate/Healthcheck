# Start of Settings
# End of Settings

$Title          = 'AD Recycle Bin Enabled'
$Header         = 'Forest-wide AD Recycle Bin optional feature state'
$Comments       = 'AD Recycle Bin (introduced in Server 2008 R2) lets administrators undelete objects with all attributes intact, including group memberships and SID. Once enabled it cannot be disabled. Strongly recommended for every domain at Forest Functional Level >= 2008 R2.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = 'B3 Active Directory'
$Severity       = 'P2'
$Recommendation = "If disabled: Enable-ADOptionalFeature 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target '<forest_root>'. One-time, irreversible. Validate restore procedure: Get-ADObject -SearchBase 'CN=Deleted Objects,DC=...' -IncludeDeletedObjects."

if (-not (Test-Path Variable:Global:ADForestFqdn) -or -not $Global:ADForestFqdn) { return }
try { Import-Module ActiveDirectory -ErrorAction Stop } catch { return }

$adArgs = @{ Server = $(if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { $Global:ADForestFqdn }) }
if (Test-Path Variable:Global:ADCredential) { $adArgs.Credential = $Global:ADCredential }

try {
    $forest = Get-ADForest -Identity $Global:ADForestFqdn @adArgs -ErrorAction Stop
    $rb = Get-ADOptionalFeature -Identity 'Recycle Bin Feature' @adArgs -ErrorAction SilentlyContinue
    $enabled = $false
    $scope = ''
    if ($rb -and $rb.EnabledScopes -and $rb.EnabledScopes.Count -gt 0) {
        $enabled = $true
        $scope = ($rb.EnabledScopes -join ', ')
    }
    [pscustomobject]@{
        Forest                       = $Global:ADForestFqdn
        ForestFunctionalLevel        = "$($forest.ForestMode)"
        RecycleBinEnabled            = $enabled
        EnabledScopes                = if ($scope) { $scope } else { '(none)' }
        RequiredFunctionalLevel      = 'Windows2008R2Forest'
        TombstoneLifetimeDaysApprox  = 'see plugin 23'
        Status                       = if ($enabled) { 'OK (enabled)' } else { 'BAD (recycle bin DISABLED)' }
    }

    # Also list any other optional features that ARE enabled (PAM, etc.)
    $allFeats = @(Get-ADOptionalFeature -Filter * @adArgs -ErrorAction SilentlyContinue)
    foreach ($f in $allFeats) {
        if ($f.Name -ne 'Recycle Bin Feature') {
            $on = ($f.EnabledScopes -and $f.EnabledScopes.Count -gt 0)
            [pscustomobject]@{
                Forest                       = $Global:ADForestFqdn
                ForestFunctionalLevel        = "$($forest.ForestMode)"
                RecycleBinEnabled            = "(other feature: $($f.Name))"
                EnabledScopes                = if ($on) { ($f.EnabledScopes -join ', ') } else { '(disabled)' }
                RequiredFunctionalLevel      = "$($f.RequiredForestMode)"
                TombstoneLifetimeDaysApprox  = ''
                Status                       = if ($on) { 'OK (enabled)' } else { 'INFO (available)' }
            }
        }
    }
} catch {
    [pscustomobject]@{ Forest=$Global:ADForestFqdn; Status=$_.Exception.Message }
}

$TableFormat = @{
    RecycleBinEnabled = { param($v,$row) if ($v -eq $true) { 'ok' } elseif ($v -eq $false) { 'bad' } else { '' } }
    Status            = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'BAD') { 'bad' } else { '' } }
}
