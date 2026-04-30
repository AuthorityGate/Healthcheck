# Start of Settings
# End of Settings

$Title          = "DEM Privilege Elevation Rules"
$Header         = "[count] privilege-elevation rule(s) defined"
$Comments       = "Every Privilege Elevation rule from DEM\\PrivilegeElevation. Rules grant temporary admin rights to specific apps for non-admin users. Over-broad rules (e.g., allowing CMD.EXE) defeat least-privilege."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "92 Dynamic Environment Manager"
$Severity       = "P2"
$Recommendation = "Audit all rules. Validate: target executable is signed; condition narrows scope (specific user group); auto-approve flag is OFF for high-risk apps. Document each rule's business owner."

if (-not $Global:DEMConfigShare -or -not (Test-Path $Global:DEMConfigShare)) {
    [pscustomobject]@{ Note='DEMConfigShare not set or unreachable.' }
    return
}
$path = Join-Path $Global:DEMConfigShare 'PrivilegeElevation'
if (-not (Test-Path $path)) {
    [pscustomobject]@{ Note='No PrivilegeElevation folder - feature not in use.' }
    return
}

foreach ($x in (Get-ChildItem -Path $path -Recurse -Filter *.xml -ErrorAction SilentlyContinue)) {
    $name=''; $tgt=''; $cond=''; $ruleType=''; $autoApprove=''
    try {
        [xml]$xml = Get-Content -LiteralPath $x.FullName -ErrorAction Stop
        $rule = $xml.SelectSingleNode('//PrivilegeElevationRule')
        if ($rule) {
            $name = $rule.SelectSingleNode('Name').InnerText
            $tgt  = $rule.SelectSingleNode('Path').InnerText
            $ruleType = $rule.GetAttribute('Type')
            $autoApprove = $rule.SelectSingleNode('AutoApprove').InnerText
            $cond = $rule.SelectSingleNode('Condition').InnerText
        }
    } catch { }
    [pscustomobject]@{
        Name        = if ($name) { $name } else { $x.BaseName }
        Type        = $ruleType
        Target      = $tgt
        AutoApprove = $autoApprove
        Condition   = if ($cond) { $cond.Substring(0, [Math]::Min(60, $cond.Length)) } else { '' }
        File        = $x.Name
    }
}

$TableFormat = @{
    AutoApprove = { param($v,$row) if ($v -match 'true|yes|1') { 'warn' } else { '' } }
}
