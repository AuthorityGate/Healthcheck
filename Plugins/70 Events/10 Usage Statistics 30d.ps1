# Start of Settings
# End of Settings

$Title          = "Horizon Usage Statistics (30 day)"
$Header         = "Usage statistics rollup from Horizon monitor endpoint"
$Comments       = "Pulls /v1/monitor/usage-statistics which returns concurrent connection counts and peak counts. Used for capacity-trend reports and license-usage justification when planning subscription renewals."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "70 Events"
$Severity       = "Info"
$Recommendation = "Compare the peak CCU values to the licensed CCU. Sustained > 80% utilization warrants a license expansion. Sudden growth >2x prior month indicates a new wave of users joined - confirm IT is aware."

if (-not (Get-HVRestSession)) { return }

$summary = $null
try { $summary = Get-HVUsageStatistics } catch { }
if (-not $summary) {
    [pscustomobject]@{ Note = 'Usage-statistics endpoint not available on this Horizon build.' }
    return
}

# Schema flatten - the response has nested counts
$rows = @()
foreach ($prop in $summary.PSObject.Properties) {
    if ($null -ne $prop.Value -and ($prop.Value -is [int] -or $prop.Value -is [long] -or $prop.Value -is [double])) {
        $rows += [pscustomobject]@{ Metric = $prop.Name; Value = $prop.Value }
    }
}
$rows
