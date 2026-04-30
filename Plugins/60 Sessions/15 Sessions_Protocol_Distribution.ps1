# Start of Settings
# End of Settings

$Title          = 'Active Session Protocol Distribution'
$Header         = "Active session counts by display protocol"
$Comments       = "Distribution of active Horizon sessions across protocols (Blast Extreme, PCoIP, RDP). Modern default = Blast Extreme. PCoIP > 10% = legacy footprint to phase out. Heavy RDP = unusual; investigate."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '60 Sessions'
$Severity       = 'P3'
$Recommendation = "Default protocol per pool to Blast Extreme. PCoIP only as fallback for client compat. Track migration progress quarterly."

if (-not (Get-HVRestSession)) { return }

try { $sessions = Invoke-HVRest -Path '/v1/inventory/sessions' -NoPaging } catch { return }
if (-not $sessions) { return }

@($sessions) | Group-Object protocol | ForEach-Object {
    $count = $_.Count
    $total = @($sessions).Count
    [pscustomobject]@{
        Protocol      = $_.Name
        Sessions      = $count
        Percentage    = if ($total -gt 0) { [math]::Round(($count / $total) * 100, 1) } else { 0 }
        Note          = switch -Regex ($_.Name) {
            'BLAST'   { 'Modern default' }
            'PCOIP'   { 'Legacy - migrate to Blast' }
            'RDP'     { 'Console/RDP fallback' }
            default   { '' }
        }
    }
}
