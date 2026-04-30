# Start of Settings
# End of Settings

$Title          = "DEM Application Settings Coverage"
$Header         = "[count] application configured under DEM\\General"
$Comments       = "Walks DEM\\General\\<Category>\\*.xml and surfaces every application configuration captured: app name, target executable, capture mode, predefined-settings flag, condition tags. This is the single most important DEM inventory - it directly answers 'is this app being managed by DEM?'."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "92 Dynamic Environment Manager"
$Severity       = "Info"
$Recommendation = "Apps shown but not actively used should be archived; apps in production with no XML here are NOT being managed by DEM (default-profile fallback). Validate against the customer's app-portfolio map."

if (-not $Global:DEMConfigShare -or -not (Test-Path $Global:DEMConfigShare)) {
    [pscustomobject]@{ Note='DEMConfigShare not set or unreachable.' }
    return
}
$general = Join-Path $Global:DEMConfigShare 'General'
if (-not (Test-Path $general)) {
    [pscustomobject]@{ Note='No General folder under the DEM share - no app configs deployed.' }
    return
}

$rows = @()
foreach ($cat in (Get-ChildItem -Path $general -Directory -ErrorAction SilentlyContinue)) {
    foreach ($x in (Get-ChildItem -Path $cat.FullName -Filter *.xml -ErrorAction SilentlyContinue)) {
        $title = $x.BaseName
        $tgt = ''; $caps = ''; $cond = ''
        try {
            [xml]$xml = Get-Content -LiteralPath $x.FullName -ErrorAction Stop
            if ($xml.flexsettings) {
                $title = $xml.flexsettings.applicationtitle ; if (-not $title) { $title = $x.BaseName }
                $tgt   = $xml.flexsettings.applicationexe
                # Folder/registry coverage hints
                $caps  = "$(($xml.flexsettings.SelectSingleNode('//FolderTrees')).ChildNodes.Count) folder(s), $(($xml.flexsettings.SelectSingleNode('//RegistryTrees')).ChildNodes.Count) registry root(s)"
                $cond  = ''
                if ($xml.flexsettings.condition -and $xml.flexsettings.condition.InnerText) { $cond = $xml.flexsettings.condition.InnerText.Substring(0, [Math]::Min(60, $xml.flexsettings.condition.InnerText.Length)) }
            }
        } catch { }
        $rows += [pscustomobject]@{
            Category   = $cat.Name
            Title      = $title
            TargetExe  = $tgt
            Coverage   = $caps
            Condition  = $cond
            File       = $x.Name
            LastModified = $x.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        }
    }
}
if ($rows.Count -eq 0) {
    [pscustomobject]@{ Note='No application XMLs found.' }
    return
}
$rows | Sort-Object Category, Title
