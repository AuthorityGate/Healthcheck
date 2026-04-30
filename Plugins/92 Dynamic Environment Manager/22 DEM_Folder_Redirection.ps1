# Start of Settings
# End of Settings

$Title          = "DEM Folder Redirection Definitions"
$Header         = "[count] folder-redirection definition(s)"
$Comments       = "Every folder redirection rule from DEM\\FolderRedirection - which Windows shell folder maps to which UNC target, with optional offline-files / exclusions. Ensures redirected folders match the customer's expected UNC paths post-upgrade."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "92 Dynamic Environment Manager"
$Severity       = "Info"
$Recommendation = "After any storage / file-server migration, every redirection target needs to be updated. Redirections to a server that DNS no longer resolves silently break user data flow."

if (-not $Global:DEMConfigShare -or -not (Test-Path $Global:DEMConfigShare)) {
    [pscustomobject]@{ Note='DEMConfigShare not set or unreachable.' }
    return
}
$path = Join-Path $Global:DEMConfigShare 'FolderRedirection'
if (-not (Test-Path $path)) {
    [pscustomobject]@{ Note='No FolderRedirection folder - feature not in use.' }
    return
}

foreach ($x in (Get-ChildItem -Path $path -Recurse -Filter *.xml -ErrorAction SilentlyContinue)) {
    try {
        [xml]$xml = Get-Content -LiteralPath $x.FullName -ErrorAction Stop
        foreach ($rule in $xml.SelectNodes('//FolderRedirection')) {
            [pscustomobject]@{
                Folder        = $rule.GetAttribute('Type')
                TargetPath    = $rule.SelectSingleNode('Path').InnerText
                OfflineFiles  = $rule.SelectSingleNode('OfflineFiles').InnerText
                MoveContents  = $rule.SelectSingleNode('MoveContents').InnerText
                Condition     = if ($rule.SelectSingleNode('Condition')) { $rule.SelectSingleNode('Condition').InnerText } else { '' }
                File          = $x.Name
            }
        }
    } catch {
        [pscustomobject]@{ Folder='(parse error)'; TargetPath=$x.Name; OfflineFiles=''; MoveContents=''; Condition=$_.Exception.Message; File=$x.Name }
    }
}
