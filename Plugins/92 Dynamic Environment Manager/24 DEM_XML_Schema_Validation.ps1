# Start of Settings
# Cap on number of XMLs to parse so a 5000-app share doesn't blow up the report.
$MaxXmlsScanned = 1000
# End of Settings

$Title          = 'DEM XML Schema Validation'
$Header         = '[count] DEM XML(s) failed to parse'
$Comments       = "Walks every *.xml under the DEM Configuration share and tries to load it as XML. Surfaces any file that won't parse - typical causes: hand-edited file with stray characters, mid-write power loss, copy-paste from a non-DEM source. A broken XML silently disables that one app's customization (FlexEngine logs an error but the user sees default behavior)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P3'
$Recommendation = "Open the file in DEM Management Console and re-save - the console rejects malformed XML at save time. If the file came from a partner / template, re-import the canonical version."

if (-not $Global:DEMConfigShare -or -not (Test-Path $Global:DEMConfigShare)) {
    [pscustomobject]@{ Note='DEMConfigShare not set or unreachable.' }
    return
}

$xmls = @(Get-ChildItem -Path $Global:DEMConfigShare -Recurse -Filter *.xml -File -ErrorAction SilentlyContinue)
if ($xmls.Count -eq 0) {
    [pscustomobject]@{ Note='No XML files found under share.' }
    return
}
if ($xmls.Count -gt $MaxXmlsScanned) {
    $xmls = $xmls | Select-Object -First $MaxXmlsScanned
}

$failures = New-Object System.Collections.ArrayList
foreach ($x in $xmls) {
    try { [void][xml](Get-Content -LiteralPath $x.FullName -Raw -ErrorAction Stop) }
    catch {
        $rel = $x.FullName.Substring($Global:DEMConfigShare.Length).TrimStart('\')
        [void]$failures.Add([pscustomobject]@{
            File         = $rel
            ParseError   = $_.Exception.Message.Substring(0, [Math]::Min(200, $_.Exception.Message.Length))
            SizeBytes    = $x.Length
            LastModified = $x.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        })
    }
}

if ($failures.Count -eq 0) {
    [pscustomobject]@{ Note = "All $($xmls.Count) XML(s) parsed cleanly." ; ScannedCount = $xmls.Count ; FailCount = 0 }
    return
}
$failures
