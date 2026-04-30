#Requires -Version 5.1
<#
    HtmlReport.psm1
    Renders the AuthorityGate HealthCheck report. Collapsible sections + severity
    colour bars, with VHA-style "Severity P1/P2/P3" badges driven by
    per-plugin metadata.
#>

function ConvertTo-HVSafeHtml {
    param([string]$s)
    if ($null -eq $s) { return '' }
    [System.Web.HttpUtility]::HtmlEncode($s)
}

# Auto-link 'KB 12345' / 'KB12345' patterns to https://kb.vmware.com/s/article/12345
# Run AFTER HtmlEncode so we don't break entity escaping. Encoded text is safe to
# regex-replace against because plain digits + 'KB' aren't entity-encoded.
function ConvertTo-HVKbLinkedHtml {
    param([string]$EncodedHtml)
    if (-not $EncodedHtml) { return '' }
    [regex]::Replace($EncodedHtml, '\bKB\s*(\d{4,7})\b', {
        param($m)
        $id = $m.Groups[1].Value
        "<a href='https://kb.vmware.com/s/article/$id' target='_blank' style='color:#0a3d62;text-decoration:underline'>KB $id</a>"
    })
}

function ConvertTo-HVTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [hashtable]$CellRules
    )
    if (-not $InputObject) { return '' }
    $rows = @($InputObject)
    if ($rows.Count -eq 0) { return '' }

    $cols = @($rows[0].PSObject.Properties.Name)
    $sb   = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<table class="data"><thead><tr>')
    foreach ($c in $cols) {
        [void]$sb.AppendFormat('<th>{0}</th>', (ConvertTo-HVSafeHtml $c))
    }
    [void]$sb.Append('</tr></thead><tbody>')
    foreach ($r in $rows) {
        [void]$sb.Append('<tr>')
        foreach ($c in $cols) {
            $v = $r.$c
            $cls = ''
            if ($CellRules -and $CellRules.ContainsKey($c)) {
                $cls = & $CellRules[$c] $v $r
            }
            $txt = if ($v -is [bool])     { $v.ToString() }
                   elseif ($v -is [datetime]) { $v.ToString('yyyy-MM-dd HH:mm') }
                   elseif ($null -eq $v)  { '' }
                   else                   { $v.ToString() }
            [void]$sb.AppendFormat('<td class="{0}">{1}</td>', $cls, (ConvertTo-HVSafeHtml $txt))
        }
        [void]$sb.Append('</tr>')
    }
    [void]$sb.Append('</tbody></table>')
    $sb.ToString()
}

function ConvertTo-HVList {
    param($InputObject)
    if (-not $InputObject) { return '' }
    $rows = @($InputObject)
    if ($rows.Count -eq 0) { return '' }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<dl class="kv">')
    foreach ($r in $rows) {
        foreach ($p in $r.PSObject.Properties) {
            [void]$sb.AppendFormat('<dt>{0}</dt><dd>{1}</dd>',
                (ConvertTo-HVSafeHtml $p.Name),
                (ConvertTo-HVSafeHtml ([string]$p.Value)))
        }
    }
    [void]$sb.Append('</dl>')
    $sb.ToString()
}

function New-HVReport {
<#
    .SYNOPSIS
    Build an HTML report from an array of plugin-result objects.
    Each plugin result carries: Title, Header, Comments, Display, Author,
    PluginVersion, PluginCategory, Severity, Recommendation, Details, Duration,
    Error.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Results,
        [Parameter(Mandatory)][string]$Server,
        [string]$Title = "Horizon Health Check",
        [hashtable]$Meta = @{},
        [string[]]$ConnectedBackends = @()
    )

    # Locate logo asset (base64 + PNG file). Module dir is .../Modules/, project root is parent.
    $assetsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets'
    $logoB64File = Join-Path $assetsDir 'AuthorityGate.b64.txt'
    $logoB64 = if (Test-Path $logoB64File) { (Get-Content $logoB64File -Raw).Trim() } else { '' }

    $generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'

    # Tally findings by severity. OK = plugins that ran clean (no error,
    # zero detail rows, or detail rows produced exclusively by 'show all
    # entities' dashboards where every row is in OK status). For tile
    # purposes any plugin with non-zero details counts toward its declared
    # severity; only plugins with zero rows AND no error count as OK.
    $sevCounts = [ordered]@{ P1 = 0; P2 = 0; P3 = 0; Info = 0; OK = 0 }
    foreach ($r in $Results) {
        $cnt = 0; if ($r.Details) { $cnt = @($r.Details).Count }
        if ($r.Error) {
            # Errors always count as P1 in the tile so the operator notices
            if ($sevCounts.Contains('P1')) { $sevCounts['P1']++ }
            continue
        }
        if ($cnt -eq 0) {
            $sevCounts['OK']++
        } elseif ($sevCounts.Contains($r.Severity)) {
            $sevCounts[$r.Severity]++
        } else {
            $sevCounts['Info']++
        }
    }
    $totalCount = 0
    foreach ($k in $sevCounts.Keys) { $totalCount += $sevCounts[$k] }

    $css = @'
<style>
  body{font-family:Segoe UI,Arial,sans-serif;margin:0;padding:0;background:#f4f6f8;color:#222;}
  header{background:linear-gradient(90deg,#ffffff 0%,#fbf6e8 28%,#d4a82a 70%,#8a6914 100%);color:#1c1e21;padding:18px 28px;display:flex;align-items:center;gap:18px;border-bottom:3px solid #6b5210;}
  header img.logo{height:56px;width:auto;background:transparent;padding:0;}
  header .htext{flex:1;}
  header h1{margin:0;font-size:22px;color:#000000;font-weight:700;}
  header .meta{font-size:12px;color:#1c1e21;margin-top:4px;}
  header a.site{color:#000000;text-decoration:none;border-bottom:1px dotted #1c1e21;font-weight:600;}
  header a.site:hover{opacity:.85;}
  .summary{display:flex;gap:12px;padding:20px 28px;background:#fff;border-bottom:1px solid #ddd;flex-wrap:wrap;}
  .badge{padding:10px 16px;border-radius:6px;color:#fff;min-width:90px;text-align:center;
         border:none;font-family:inherit;font-size:13px;cursor:pointer;
         transition:transform .08s ease, box-shadow .15s ease, opacity .15s ease;
         opacity:.92;}
  .badge:hover{transform:translateY(-1px);box-shadow:0 4px 10px rgba(0,0,0,.18);opacity:1;}
  .badge.active{outline:3px solid #1c1e21;outline-offset:2px;opacity:1;
                box-shadow:0 4px 12px rgba(0,0,0,.22);}
  .badge .n{font-size:24px;font-weight:600;display:block;}
  .badge.all{background:#34495e;}
  .badge.p1{background:#c0392b;}
  .badge.p2{background:#e67e22;}
  .badge.p3{background:#f1c40f;color:#222;}
  .badge.info{background:#3498db;}
  .badge.ok{background:#27ae60;}
  .toc{padding:14px 28px;background:#fff;border-bottom:1px solid #ddd;}
  .toc a{margin-right:14px;text-decoration:none;color:#0a3d62;font-size:13px;}
  section.cat{padding:14px 28px;border-top:1px solid #ddd;}
  section.cat h2{margin:0 0 10px 0;color:#0a3d62;font-size:18px;}
  details.plugin{background:#fff;border:1px solid #ddd;border-left:6px solid #bbb;
                 border-radius:4px;margin:10px 0;padding:10px 14px;}
  details.plugin[data-sev=P1]{border-left-color:#c0392b;}
  details.plugin[data-sev=P2]{border-left-color:#e67e22;}
  details.plugin[data-sev=P3]{border-left-color:#f1c40f;}
  details.plugin[data-sev=Info]{border-left-color:#3498db;}
  details.plugin[data-sev=OK]{border-left-color:#27ae60;}
  details.plugin summary{cursor:pointer;font-weight:600;color:#222;}
  details.plugin summary .pill{display:inline-block;padding:2px 8px;font-size:11px;
       border-radius:10px;background:#888;color:#fff;margin-left:8px;}
  details.plugin summary .pill.P1{background:#c0392b;}
  details.plugin summary .pill.P2{background:#e67e22;}
  details.plugin summary .pill.P3{background:#f1c40f;color:#222;}
  details.plugin summary .pill.Info{background:#3498db;}
  details.plugin summary .pill.OK{background:#27ae60;}
  details.plugin summary .count{color:#666;font-weight:400;margin-left:6px;}
  details.plugin .body{margin-top:10px;font-size:13px;}
  details.plugin .body p.comment{color:#555;font-style:italic;}
  details.plugin .body p.recommend{background:#fff8d6;border-left:3px solid #f1c40f;padding:6px 10px;}
  details.plugin .body p.error{background:#fde2e2;border-left:3px solid #c0392b;padding:6px 10px;}
  table.data{border-collapse:collapse;width:100%;font-size:12px;margin-top:6px;}
  table.data th{background:#eef1f5;text-align:left;padding:6px 8px;border-bottom:1px solid #ccc;}
  table.data td{padding:6px 8px;border-bottom:1px solid #eee;vertical-align:top;}
  table.data td.bad{background:#fde2e2;}
  table.data td.warn{background:#fff8d6;}
  table.data td.ok{background:#e6f5e9;}
  dl.kv dt{font-weight:600;float:left;width:200px;}
  dl.kv dd{margin-left:210px;}
  footer{padding:18px 28px;font-size:11px;color:#666;}
  footer code{background:#eef1f5;padding:2px 4px;border-radius:3px;}
</style>
'@

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("<!DOCTYPE html><html><head><meta charset='utf-8'><title>$([System.Web.HttpUtility]::HtmlEncode($Title)) - $Server</title>$css</head><body>")

    $logoTag = if ($logoB64) {
        "<img class='logo' alt='AuthorityGate' src='data:image/png;base64,$logoB64'>"
    } else { '' }
    $backendsLine = if ($ConnectedBackends -and $ConnectedBackends.Count -gt 0) {
        "Connected: $((($ConnectedBackends | ForEach-Object { ConvertTo-HVSafeHtml $_ }) -join ', '))"
    } else {
        "No live backend connections - report shows skip / metadata only"
    }
    [void]$sb.AppendFormat("<header>{0}<div class='htext'><h1>{1}</h1><div class='meta'>Target: {2} &middot; {3} &middot; Generated: {4} &middot; <a class='site' href='https://www.authoritygate.com' target='_blank'>www.authoritygate.com</a></div></div></header>",
        $logoTag,
        (ConvertTo-HVSafeHtml $Title),
        (ConvertTo-HVSafeHtml $Server),
        $backendsLine,
        $generated)

    # Summary tiles - clickable filters. Click a tile to show only findings
    # of that severity; click ALL to clear the filter. Default state on
    # page load is ALL (every finding visible).
    [void]$sb.Append("<div class='summary'>")
    [void]$sb.AppendFormat("<button type='button' class='badge all active' data-filter='ALL'><span class='n'>{0}</span>ALL</button>", $totalCount)
    foreach ($k in $sevCounts.Keys) {
        $cls = $k.ToLower()
        [void]$sb.AppendFormat("<button type='button' class='badge {0}' data-filter='{1}'><span class='n'>{2}</span>{1}</button>", $cls, $k, $sevCounts[$k])
    }
    [void]$sb.Append("</div>")

    # Group by category
    $byCat = $Results | Group-Object PluginCategory | Sort-Object Name

    # TOC
    [void]$sb.Append("<div class='toc'>")
    foreach ($g in $byCat) {
        [void]$sb.AppendFormat("<a href='#cat-{0}'>{1} ({2})</a>",
            ([uri]::EscapeDataString($g.Name)),
            (ConvertTo-HVSafeHtml $g.Name),
            $g.Count)
    }
    [void]$sb.Append("</div>")

    # Sections
    foreach ($g in $byCat) {
        [void]$sb.AppendFormat("<section class='cat' id='cat-{0}'><h2>{1}</h2>",
            ([uri]::EscapeDataString($g.Name)),
            (ConvertTo-HVSafeHtml $g.Name))

        foreach ($r in ($g.Group | Sort-Object Title)) {
            $details = @($r.Details)
            $count   = $details.Count
            $sev     = if ($r.Error)        { 'P1' }
                       elseif ($count -eq 0) { 'OK' }
                       else                  { $r.Severity }
            if (-not $sev) { $sev = 'Info' }

            $header = if ($r.Header) { $r.Header -replace '\[count\]', $count } else { $r.Title }

            [void]$sb.AppendFormat("<details class='plugin' data-sev='{0}'{1}>", $sev,
                $(if ($sev -in 'P1','P2') { ' open' } else { '' }))
            [void]$sb.AppendFormat("<summary>{0} <span class='pill {1}'>{1}</span><span class='count'>({2} item{3})</span></summary>",
                (ConvertTo-HVSafeHtml $r.Title), $sev, $count, $(if ($count -eq 1) { '' } else { 's' }))

            [void]$sb.Append("<div class='body'>")
            if ($header -ne $r.Title) {
                [void]$sb.AppendFormat("<p><strong>{0}</strong></p>", (ConvertTo-HVSafeHtml $header))
            }
            if ($r.Comments) {
                [void]$sb.AppendFormat("<p class='comment'>{0}</p>", (ConvertTo-HVKbLinkedHtml (ConvertTo-HVSafeHtml $r.Comments)))
            }
            if ($r.Error) {
                [void]$sb.AppendFormat("<p class='error'><strong>Plugin error:</strong> {0}</p>",
                    (ConvertTo-HVSafeHtml $r.Error))
            } else {
                if ($count -eq 0) {
                    [void]$sb.Append("<p>No findings.</p>")
                } else {
                    switch ($r.Display) {
                        'Table' { [void]$sb.Append((ConvertTo-HVTable -InputObject $details -CellRules $r.TableFormat)) }
                        'List'  { [void]$sb.Append((ConvertTo-HVList  -InputObject $details)) }
                        default { [void]$sb.Append((ConvertTo-HVTable -InputObject $details -CellRules $r.TableFormat)) }
                    }
                }
                if ($r.Recommendation) {
                    [void]$sb.AppendFormat("<p class='recommend'><strong>Recommendation:</strong> {0}</p>",
                        (ConvertTo-HVKbLinkedHtml (ConvertTo-HVSafeHtml $r.Recommendation)))
                }
            }

            [void]$sb.AppendFormat("<p style='font-size:10px;color:#888;margin-top:8px'>Author: {0} &middot; v{1} &middot; ran in {2:0.00}s</p>",
                (ConvertTo-HVSafeHtml $r.Author), $r.PluginVersion, $r.Duration)

            [void]$sb.Append("</div></details>")
        }
        [void]$sb.Append("</section>")
    }

    [void]$sb.Append("<footer>AuthorityGate HealthCheck &middot; <a href='https://www.authoritygate.com' target='_blank'>AuthorityGate</a></footer>")

    # Severity-filter behavior: clicking a summary tile narrows the visible
    # findings to that severity. Clicking ALL shows everything. Category
    # sections with no visible plugins are hidden, as are TOC links to
    # those sections, so the report stays tidy at every filter state.
    [void]$sb.Append(@"
<script>
(function(){
  function applyFilter(f) {
    document.querySelectorAll('.badge[data-filter]').forEach(function(b){
      b.classList.toggle('active', b.dataset.filter === f);
    });
    document.querySelectorAll('details.plugin').forEach(function(p){
      var s = p.getAttribute('data-sev') || '';
      p.style.display = (f === 'ALL' || s === f) ? '' : 'none';
    });
    document.querySelectorAll('section.cat').forEach(function(sec){
      var anyVisible = false;
      sec.querySelectorAll('details.plugin').forEach(function(p){
        if (p.style.display !== 'none') anyVisible = true;
      });
      sec.style.display = anyVisible ? '' : 'none';
      var id = sec.id || '';
      if (id) {
        document.querySelectorAll('.toc a[href="#' + id + '"]').forEach(function(a){
          a.style.display = anyVisible ? '' : 'none';
        });
      }
    });
  }
  document.querySelectorAll('.badge[data-filter]').forEach(function(b){
    b.addEventListener('click', function(){ applyFilter(b.dataset.filter); });
  });
})();
</script>
"@)
    [void]$sb.Append("</body></html>")
    $sb.ToString()
}

Export-ModuleMember -Function New-HVReport, ConvertTo-HVTable, ConvertTo-HVList, ConvertTo-HVSafeHtml
