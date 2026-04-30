# Start of Settings
# End of Settings

$Title          = "vIDM Access Policies / Auth Rules"
$Header         = "[count] access policy(ies) governing app sign-in"
$Comments       = "Access policies tell vIDM how to authenticate a user when they sign into a particular app or category. Each policy is a list of rules in priority order (network range, device-type, group membership). The DEFAULT_ACCESS_POLICY is the catch-all - everything not matched by a specific policy uses this. Mis-configured DEFAULT can let users in without MFA."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B5 Workspace ONE Access"
$Severity       = "P2"
$Recommendation = "DEFAULT_ACCESS_POLICY should require MFA for external (UAG-fronted) traffic. Per-app policies should pin sensitive apps to phishing-resistant MFA (FIDO2 / smart card) for privileged users."

if (-not (Get-VIDMRestSession)) { return }
$pols = @(Get-VIDMAccessPolicy)
if ($pols.Count -eq 0) {
    [pscustomobject]@{ Note = 'No access policies returned. Check the OAuth client has Admin scope.' }
    return
}

foreach ($p in $pols) {
    $ruleCount = if ($p.rules) { @($p.rules).Count } else { 0 }
    $methodSummary = if ($p.rules) {
        ($p.rules | ForEach-Object { ($_.authMethods -join '+') } | Sort-Object -Unique) -join ' | '
    } else { '' }
    [pscustomobject]@{
        Name        = $p.name
        Description = if ($p.description) { $p.description.Substring(0,[Math]::Min(80,$p.description.Length)) } else { '' }
        IsDefault   = ($p.name -eq 'DEFAULT_ACCESS_POLICY')
        RuleCount   = $ruleCount
        AuthMethodsSeen = $methodSummary
        ApplicationCount = if ($p.applications) { @($p.applications).Count } else { 0 }
    }
}

$TableFormat = @{
    IsDefault = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
}
