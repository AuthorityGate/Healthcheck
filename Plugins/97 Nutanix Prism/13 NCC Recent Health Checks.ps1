# Start of Settings
# End of Settings

$Title          = "Nutanix NCC Recent Health Checks"
$Header         = "Latest Nutanix Cluster Check (NCC) result summary"
$Comments       = "NCC is Nutanix's built-in health-check engine that runs hundreds of cluster sanity probes (storage health, networking, hardware, AOS / hypervisor compatibility). Plugin reports the most-recent NCC summary so the audit picks up cluster-side issues NCC has already surfaced. Doesn't initiate a new run; reports what NCC last said."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "P2"
$Recommendation = "NCC should run weekly automatically (Cluster -> Health -> Run Checks). Critical-status checks need immediate triage. WARN-status checks should be reviewed against Nutanix KB for the recommended action - some are intentionally suppressed and should be confirmed."

if (-not (Get-NTNXRestSession)) { return }
# NCC results live at /api/nutanix/v3/ncc/results in newer PC builds; older builds expose via /PrismGateway/services/rest/v2.0/health/checks
$results = $null
foreach ($p in @('/ncc/results','/health_checks/results')) {
    try { $results = Invoke-NTNXRest -Path $p -ErrorAction SilentlyContinue; if ($results) { break } } catch { }
}
if (-not $results) {
    [pscustomobject]@{ Note='NCC results endpoint not exposed on this Prism build. Run NCC via UI: Cluster -> Health -> Actions -> Run NCC checks.' }
    return
}

# Group by status
$rows = New-Object System.Collections.ArrayList
$entities = if ($results.entities) { @($results.entities) } else { @($results) }
$bySeverity = $entities | Group-Object severity_level
foreach ($g in $bySeverity) {
    [void]$rows.Add([pscustomobject]@{
        SeverityLevel = $g.Name
        Count         = $g.Count
        SampleChecks  = ($g.Group | Select-Object -First 3 | ForEach-Object { $_.title }) -join '; '
    })
}
if ($rows.Count -eq 0) {
    [pscustomobject]@{ Note='NCC results returned no severity groups.' }
    return
}
$rows

$TableFormat = @{
    SeverityLevel = { param($v,$row) if ($v -match 'critical') { 'bad' } elseif ($v -match 'warning') { 'warn' } elseif ($v -match 'info|pass') { 'ok' } else { '' } }
}
