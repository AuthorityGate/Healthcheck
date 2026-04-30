# Start of Settings
# End of Settings

$Title          = 'Recently Failed Tasks'
$Header         = '[count] task(s) failed in the last 24 hours'
$Comments       = 'Failed vCenter tasks (clone/migrate/poweron) often correlate with bigger infrastructure issues.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P2'
$Recommendation = 'Drill in: vCenter -> Recent Tasks. Group by error message; address root cause.'

if (-not $Global:VCConnected) { return }
$start = (Get-Date).AddHours(-24)
Get-VIEvent -Start $start -Types Error -MaxSamples 200 -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        Time     = $_.CreatedTime
        User     = $_.UserName
        Type     = $_.GetType().Name
        Message  = ($_.FullFormattedMessage -replace "`r|`n",' ').Substring(0, [Math]::Min(140, $_.FullFormattedMessage.Length))
    }
}
