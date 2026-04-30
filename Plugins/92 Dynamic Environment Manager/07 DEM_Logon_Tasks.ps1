# Start of Settings
# End of Settings

$Title          = 'DEM Logon Tasks'
$Header         = '[count] DEM logon task(s)'
$Comments       = 'Logon tasks lengthen logon path. Best-practice cap at < 10 tasks.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P3'
$Recommendation = 'Migrate logon tasks to triggered tasks bound to specific app launches.'

$share = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware UEM\Agent\FlexEngine' -ErrorAction SilentlyContinue).ConfigShare
if (-not $share -or -not (Test-Path $share)) { return }
$lt = Get-ChildItem -Path (Join-Path $share 'LogonTasks') -Recurse -ErrorAction SilentlyContinue
if (-not $lt) { return }
[pscustomobject]@{ LogonTaskCount = $lt.Count }
