# Start of Settings
# Operator hint: $Global:DEMConfigShare = '\\fileserver\dem-config'
# Most real-world DEM shares hold everything under <root>\General\<Category>\App.xml.
# Other content types (LogonTasks, PrivilegeElevation, Triggered Tasks, etc.)
# may NOT have top-level folders - they live inside the XML's root element.
# This plugin handles both layouts.
# End of Settings

$Title          = 'DEM FlexConfig Catalog'
$Header         = "[count] DEM config object(s) inventoried (by category + content type)"
$Comments       = @"
Walks the DEM share and classifies every XML in two dimensions:

1. By CATEGORY (application grouping under General\): one row per immediate subfolder of General\, with file count and last-modified.
2. By CONTENT TYPE (read from each XML's root element): flexsettings (app config), conditions, logontasks, privilege-elevation, application-blocker, folder-redirection, etc. Reflects what the file actually IS, regardless of folder placement.

Optional top-level folders (Conditions/, LogonTasks/, etc.) are only listed if they exist - DEM admin consoles vary on whether they create those.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = "92 Dynamic Environment Manager"
$Severity       = "Info"
$Recommendation = "Apps configured here represent what DEM is ACTUALLY managing for users. If a column shows 0 but the customer says 'we use that feature', the GPO may point at a different share OR the feature is delivered via a non-DEM mechanism."

if (-not (Test-Path Variable:Global:DEMConfigShare) -or -not $Global:DEMConfigShare) {
    [pscustomobject]@{ Folder = '(no DEM share configured)'; Count = ''; Note = 'Set $Global:DEMConfigShare in runner OR via GUI.' }
    return
}
$share = $Global:DEMConfigShare
if (-not (Test-Path $share)) {
    [pscustomobject]@{ Folder = $share; Count = ''; Note = 'Share not reachable.' }
    return
}

$rows = New-Object System.Collections.ArrayList

# Pass 1: walk General\<Category>\ and emit one row per category subfolder.
$general = Join-Path $share 'General'
if (Test-Path $general) {
    $catFolders = @(Get-ChildItem -Path $general -Directory -ErrorAction SilentlyContinue)
    if ($catFolders.Count -eq 0) {
        # Flat - no subfolders, just XMLs in General root
        $xmls = @(Get-ChildItem -Path $general -Filter *.xml -File -ErrorAction SilentlyContinue)
        $latest = $xmls | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        [void]$rows.Add([pscustomobject]@{
            Section = 'Application Settings (General root)'
            Item    = '(flat layout)'
            Count   = $xmls.Count
            LastModified = if ($latest) { $latest.LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { '' }
            Path    = $general
            Note    = ''
        })
    } else {
        foreach ($cat in $catFolders | Sort-Object Name) {
            $xmls = @(Get-ChildItem -Path $cat.FullName -Recurse -Filter *.xml -File -ErrorAction SilentlyContinue)
            $latest = $xmls | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            [void]$rows.Add([pscustomobject]@{
                Section = 'Application Settings (General)'
                Item    = $cat.Name
                Count   = $xmls.Count
                LastModified = if ($latest) { $latest.LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { '' }
                Path    = $cat.FullName
                Note    = ''
            })
        }
    }
}

# Pass 2: Walk the entire share, classify by XML root-element name. This
# catches content types stored INSIDE General\, OR in flat layout, OR in
# atypical folder layouts. We aggregate counts by detected type.
$allXmls = @(Get-ChildItem -Path $share -Recurse -Filter *.xml -File -ErrorAction SilentlyContinue)
$typeMap = @{}
$failedParse = 0
foreach ($x in $allXmls) {
    try {
        # Read first 2KB to detect root element without loading whole file.
        $head = Get-Content -LiteralPath $x.FullName -TotalCount 30 -ErrorAction Stop
        $headText = ($head -join "`n")
        $rootName = ''
        if ($headText -match '<\??xml[^>]*>\s*<!?[^>]*>?\s*<([a-zA-Z][a-zA-Z0-9_-]*)') { $rootName = $Matches[1] }
        elseif ($headText -match '<([a-zA-Z][a-zA-Z0-9_-]*)') { $rootName = $Matches[1] }
        if (-not $rootName) { $rootName = '(unknown)' }
        if (-not $typeMap.ContainsKey($rootName)) {
            $typeMap[$rootName] = [pscustomobject]@{ Count = 0 ; LastModified = $null }
        }
        $typeMap[$rootName].Count++
        if (-not $typeMap[$rootName].LastModified -or $x.LastWriteTime -gt $typeMap[$rootName].LastModified) {
            $typeMap[$rootName].LastModified = $x.LastWriteTime
        }
    } catch { $failedParse++ }
}
foreach ($k in ($typeMap.Keys | Sort-Object)) {
    $entry = $typeMap[$k]
    [void]$rows.Add([pscustomobject]@{
        Section = 'Content Type (XML root)'
        Item    = $k
        Count   = $entry.Count
        LastModified = if ($entry.LastModified) { $entry.LastModified.ToString('yyyy-MM-dd HH:mm') } else { '' }
        Path    = '(scan-wide)'
        Note    = ''
    })
}

# Pass 3: optional top-level folders (only emit rows if they exist).
$optionalFolders = @('Conditions','Triggered Tasks','PrivilegeElevation','ApplicationBlocker',
    'FolderRedirection','LogonTasks','ShortcutManagement','ADMXImporter','Profiles',
    'CustomConditions','EnvironmentVariables','LockedItems','SelfSupport','WelcomeMessage',
    'DriveMapping','PrinterMapping')
$presentOptional = @()
foreach ($f in $optionalFolders) {
    $path = Join-Path $share $f
    if (Test-Path $path) {
        $xmls = @(Get-ChildItem -Path $path -Recurse -Filter *.xml -File -ErrorAction SilentlyContinue)
        $latest = $xmls | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        [void]$rows.Add([pscustomobject]@{
            Section = 'Optional Top-Level Folder'
            Item    = $f
            Count   = $xmls.Count
            LastModified = if ($latest) { $latest.LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { '' }
            Path    = $path
            Note    = ''
        })
        $presentOptional += $f
    }
}
if ($presentOptional.Count -eq 0) {
    [void]$rows.Add([pscustomobject]@{
        Section = 'Optional Top-Level Folder'
        Item    = '(none present)'
        Count   = 0
        LastModified = ''
        Path    = $share
        Note    = 'No optional top-level DEM folders found - normal for shares organized purely under General\. Content types still detected by XML root element above.'
    })
}

if ($failedParse -gt 0) {
    [void]$rows.Add([pscustomobject]@{
        Section = 'Health'
        Item    = 'XMLs that failed initial scan'
        Count   = $failedParse
        LastModified = ''
        Path    = ''
        Note    = "See 'DEM XML Schema Validation' plugin for the full per-file error list."
    })
}

$rows
