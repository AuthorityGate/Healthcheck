# Start of Settings
# End of Settings

$Title          = 'DEM FlexEngine Logon Time'
$Header         = 'DEM FlexEngine last-recorded logon time'
$Comments       = 'If FlexEngine is taking > 10s on logon, profile corruption or share latency is likely.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P3'
$Recommendation = 'Tune FlexEngine.exe -refresh logon. Investigate share network path; ping share to test latency.'

$logPath = "$env:LOCALAPPDATA\VMware\FlexEngine\FlexEngine.log"
if (-not (Test-Path $logPath)) { $logPath = "$env:LOCALAPPDATA\Omnissa\FlexEngine\FlexEngine.log" }
if (-not (Test-Path $logPath)) { return }
$line = Select-String -Path $logPath -Pattern "Total time:" | Select-Object -Last 1
if ($line) {
    [pscustomobject]@{ LastLogonRecord = $line.Line }
}
