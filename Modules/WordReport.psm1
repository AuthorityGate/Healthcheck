#Requires -Version 5.1
<#
    WordReport.psm1
    Renders the AuthorityGate HealthCheck plugin-result array into a Word document via Word.Application COM automation:

        Title           : "Horizon Health Check for <pod>"
        Body            : Document version table + author
        SUMMARY         : One-paragraph executive view with severity tally
        TABLE OF CONTENTS
        Heading 1 / 2   : Per category, per plugin
        Native Word tables for each plugin's data

    Requires Microsoft Word installed locally (any 2007+ build). The doc
    is saved as .docx and Word is closed.
#>

# Word constants we use
$Script:WdStyleTitle      = -63
$Script:WdStyleHeading1   = -2
$Script:WdStyleHeading2   = -3
$Script:WdStyleHeading3   = -4
$Script:WdStyleHeading4   = -5
$Script:WdStyleBodyText   = -67
$Script:WdStyleTOC1       = -39
$Script:WdStyleTOC2       = -40
$Script:WdStyleTOC3       = -41
$Script:WdStyleNormal     = -1
$Script:WdSaveOptionsDoNotSaveChanges = 0
$Script:WdPageBreak       = 7
$Script:WdLine            = 5
$Script:WdParagraph       = 4
$Script:WdRow             = 10
$Script:WdFormatXMLDocument = 12   # .docx
$Script:WdAutoFitWindow   = 2
$Script:WdColorRed        = 255
$Script:WdColorOrange     = 26367
$Script:WdColorYellow     = 65535
$Script:WdColorGreen      = 5287936
$Script:WdColorGray       = 12632256
$Script:WdAlignParagraphCenter = 1

function Write-HVHeading {
    param($Word, [int]$Level, [string]$Text)
    switch ($Level) {
        1 { $Word.Selection.Style = $Script:WdStyleHeading1 }
        2 { $Word.Selection.Style = $Script:WdStyleHeading2 }
        3 { $Word.Selection.Style = $Script:WdStyleHeading3 }
        4 { $Word.Selection.Style = $Script:WdStyleHeading4 }
    }
    $Word.Selection.TypeText("$Text`r")
    $Word.Selection.Style = $Script:WdStyleBodyText
}

function Write-HVKeyValueTable {
    <#
        Render a single PSObject as a 2-column key/value Word table.
    #>
    param($Word, $Object)
    if (-not $Object) { return }
    $props = @($Object.PSObject.Properties)
    $tbl = $Word.ActiveDocument.Tables.Add($Word.Selection.Range, $props.Count, 2)
    $tbl.Borders.Enable = $true
    $tbl.PreferredWidthType = 2  # wdPreferredWidthPercent
    $tbl.PreferredWidth = 100
    foreach ($p in $props) {
        $Word.Selection.Font.Bold = $true
        $Word.Selection.TypeText([string]$p.Name)
        $Word.Selection.MoveRight() | Out-Null
        $Word.Selection.Font.Bold = $false
        $val = if ($null -eq $p.Value) { '' }
               elseif ($p.Value -is [datetime]) { $p.Value.ToString('yyyy-MM-dd HH:mm') }
               else { [string]$p.Value }
        $Word.Selection.TypeText($val)
        $Word.Selection.MoveRight() | Out-Null
    }
    $Word.Selection.EndKey($Script:WdLine) | Out-Null
    $Word.Selection.TypeText("`r")
}

function Write-HVDataTable {
    <#
        Render an array of PSObjects (homogeneous) as an N-row x M-col table
        with the property names as header row.
    #>
    param($Word, $Rows)
    $rowsArr = @($Rows)
    if ($rowsArr.Count -eq 0) { return }
    $cols = @($rowsArr[0].PSObject.Properties.Name)
    $tbl  = $Word.ActiveDocument.Tables.Add($Word.Selection.Range, $rowsArr.Count + 1, $cols.Count)
    $tbl.Borders.Enable = $true
    $tbl.AutoFitBehavior($Script:WdAutoFitWindow) | Out-Null

    # Header row
    foreach ($c in $cols) {
        $Word.Selection.Font.Bold = $true
        $Word.Selection.TypeText([string]$c)
        $Word.Selection.MoveRight() | Out-Null
    }
    $Word.Selection.Font.Bold = $false

    # Data rows
    foreach ($r in $rowsArr) {
        foreach ($c in $cols) {
            $v = $r.$c
            $txt = if ($null -eq $v) { '' }
                   elseif ($v -is [datetime]) { $v.ToString('yyyy-MM-dd HH:mm') }
                   elseif ($v -is [bool]) { $v.ToString() }
                   else { [string]$v }
            $Word.Selection.TypeText($txt)
            $Word.Selection.MoveRight() | Out-Null
        }
    }
    $Word.Selection.EndKey($Script:WdLine) | Out-Null
    $Word.Selection.TypeText("`r")
}

function New-HVWordReport {
<#
    .SYNOPSIS
        Build a .docx from the plugin-result array.
    .PARAMETER Results
        The same array produced by Invoke-HorizonHealthCheck.ps1.
    .PARAMETER Server
        Connection Server FQDN - appears in the title.
    .PARAMETER OutputFile
        Absolute path for the resulting .docx.
    .PARAMETER Author
        Document author (for cover page).
    .PARAMETER ShowWord
        Pass -ShowWord to keep Word visible (debugging).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Results,
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$OutputFile,
        [string]$Title  = "Horizon Health Check",
        [string]$Author = "AuthorityGate",
        [string[]]$ConnectedBackends = @(),
        [switch]$ShowWord
    )

    # Locate logo PNG
    $logoPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\AuthorityGate.png'

    Write-Verbose "Launching Word ..."
    $word = New-Object -ComObject Word.Application
    $word.Visible = [bool]$ShowWord
    $doc  = $word.Documents.Add()

    try {
        # ----- Title page -------------------------------------------------------
        # Logo (centered) before the title
        if (Test-Path $logoPath) {
            $word.Selection.ParagraphFormat.Alignment = $Script:WdAlignParagraphCenter
            try {
                $shape = $word.Selection.InlineShapes.AddPicture($logoPath, $false, $true)
                # Cap width to ~2 inches (144pt = 2 inches at 72dpi)
                if ($shape.Width -gt 144) {
                    $ratio = $shape.Height / $shape.Width
                    $shape.Width = 144
                    $shape.Height = 144 * $ratio
                }
                $word.Selection.TypeText("`r")
            } catch { Write-Verbose "Logo embed failed: $($_.Exception.Message)" }
            $word.Selection.ParagraphFormat.Alignment = 0   # left
        }
        $word.Selection.Style = $Script:WdStyleTitle
        $word.Selection.TypeText("$Title for $Server`r")
        $word.Selection.Style = $Script:WdStyleBodyText
        $word.Selection.TypeText("www.authoritygate.com`r`r")

        $word.Selection.Style = $Script:WdStyleBodyText
        $word.Selection.TypeText("Document versions:`r")
        $tblV = $doc.Tables.Add($word.Selection.Range, 2, 4)
        $tblV.Borders.Enable = $true
        foreach ($h in 'Version','Date','Author','Comment') {
            $word.Selection.Font.Bold = $true
            $word.Selection.TypeText($h)
            $word.Selection.MoveRight() | Out-Null
        }
        $word.Selection.Font.Bold = $false
        $word.Selection.TypeText('1.0');                               $word.Selection.MoveRight() | Out-Null
        $word.Selection.TypeText((Get-Date).ToString('yyyy-MM-dd'));   $word.Selection.MoveRight() | Out-Null
        $word.Selection.TypeText($Author);                             $word.Selection.MoveRight() | Out-Null
        $word.Selection.TypeText('Initial scan');                      $word.Selection.MoveRight() | Out-Null
        $word.Selection.EndKey($Script:WdLine) | Out-Null
        $word.Selection.TypeText("`r")

        # ----- SUMMARY ----------------------------------------------------------
        $word.Selection.Font.Bold = $true
        $word.Selection.TypeText("SUMMARY`r")
        $word.Selection.Font.Bold = $false
        $word.Selection.Style = $Script:WdStyleBodyText

        $sevCounts = [ordered]@{ P1 = 0; P2 = 0; P3 = 0; Info = 0 }
        $catCounts = [ordered]@{}
        foreach ($r in $Results) {
            $hits = @($r.Details).Count
            if ($hits -gt 0 -and $sevCounts.Contains($r.Severity)) { $sevCounts[$r.Severity] += $hits }
            if (-not $catCounts.Contains($r.PluginCategory)) { $catCounts[$r.PluginCategory] = 0 }
            $catCounts[$r.PluginCategory] += $hits
        }

        $word.Selection.TypeText(("Health check executed against {0} on {1}.`r" -f $Server, (Get-Date)))
        $backendsLine = if ($ConnectedBackends -and $ConnectedBackends.Count -gt 0) {
            "Connected backends: $($ConnectedBackends -join ', ')."
        } else {
            "No live backend connections - report shows skip/metadata only."
        }
        $word.Selection.TypeText("$backendsLine`r")
        $word.Selection.TypeText(("This report contains {0} plugin(s) across {1} category/categories.`r" -f $Results.Count, $catCounts.Keys.Count))
        $word.Selection.TypeText(("Severity tally:  P1: {0}   P2: {1}   P3: {2}   Info: {3}`r`r" -f `
            $sevCounts.P1, $sevCounts.P2, $sevCounts.P3, $sevCounts.Info))

        # Severity / category recap as a Word table
        $sumRows = foreach ($k in $catCounts.Keys) {
            [pscustomobject]@{ Category = $k; Findings = $catCounts[$k] }
        }
        Write-HVDataTable -Word $word -Rows $sumRows

        # ----- TOC --------------------------------------------------------------
        $word.Selection.Font.Bold = $true
        $word.Selection.TypeText("`rTABLE OF CONTENTS`r")
        $word.Selection.Font.Bold = $false
        $doc.TablesOfContents.Add($word.Selection.Range, $false, 1, 3) | Out-Null
        $word.Selection.TypeText("`r")
        $word.Selection.InsertBreak($Script:WdPageBreak)

        # ----- Sections (Heading 1 = category, Heading 2 = plugin) --------------
        $byCat = $Results | Group-Object PluginCategory | Sort-Object Name
        foreach ($g in $byCat) {
            Write-HVHeading -Word $word -Level 1 -Text $g.Name

            foreach ($r in ($g.Group | Sort-Object Title)) {
                $details = @($r.Details)
                $count   = $details.Count
                $sev     = if ($r.Error)        { 'P1' }
                           elseif ($count -eq 0) { 'OK' }
                           else                  { $r.Severity }
                if (-not $sev) { $sev = 'Info' }

                Write-HVHeading -Word $word -Level 2 -Text ("{0}  [{1}]" -f $r.Title, $sev)

                if ($r.Header) {
                    $h = $r.Header -replace '\[count\]', $count
                    $word.Selection.Font.Italic = $true
                    $word.Selection.TypeText("$h`r")
                    $word.Selection.Font.Italic = $false
                }
                if ($r.Comments) {
                    $word.Selection.TypeText("$($r.Comments)`r")
                }

                if ($r.Error) {
                    $word.Selection.Font.Color = $Script:WdColorRed
                    $word.Selection.TypeText("Plugin error: $($r.Error)`r")
                    $word.Selection.Font.Color = -16777216  # wdColorAutomatic
                } elseif ($count -eq 0) {
                    $word.Selection.Font.Color = $Script:WdColorGreen
                    $word.Selection.TypeText("No findings.`r")
                    $word.Selection.Font.Color = -16777216
                } else {
                    if ($r.Display -eq 'List' -and $count -eq 1) {
                        Write-HVKeyValueTable -Word $word -Object $details[0]
                    } else {
                        Write-HVDataTable -Word $word -Rows $details
                    }
                }

                if ($r.Recommendation -and $count -gt 0 -and -not $r.Error) {
                    $word.Selection.Font.Bold = $true
                    $word.Selection.TypeText("Recommendation: ")
                    $word.Selection.Font.Bold = $false
                    $word.Selection.TypeText("$($r.Recommendation)`r")
                }

                $word.Selection.TypeText("`r")
            }
        }

        # ----- Refresh TOC so page numbers are right ---------------------------
        if ($doc.TablesOfContents.Count -gt 0) {
            $doc.TablesOfContents.Item(1).Update()
        }

        # ----- Save -----------------------------------------------------------
        $dir = Split-Path -Parent $OutputFile
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $doc.SaveAs([ref]$OutputFile, [ref]$Script:WdFormatXMLDocument)
        Write-Verbose "Saved Word document: $OutputFile"
    }
    finally {
        if ($doc)  { try { $doc.Close([ref]$Script:WdSaveOptionsDoNotSaveChanges) } catch { } }
        if ($word) { try { $word.Quit() } catch { } }
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }

    $OutputFile
}

Export-ModuleMember -Function New-HVWordReport, Write-HVHeading, Write-HVKeyValueTable, Write-HVDataTable
