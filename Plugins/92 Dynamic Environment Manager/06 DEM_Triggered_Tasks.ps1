# Start of Settings
# End of Settings

$Title          = 'DEM Triggered Tasks'
$Header         = '[count] DEM triggered task(s)'
$Comments       = 'Triggered tasks (logon scripts, mappings, registry inject) override logon time. Audit count for sprawl.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P3'
$Recommendation = 'Reduce triggered-task count; consolidate mappings into a single .ini.'

$share = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware UEM\Agent\FlexEngine' -ErrorAction SilentlyContinue).ConfigShare
if (-not $share -or -not (Test-Path $share)) { return }
$tt = Get-ChildItem -Path (Join-Path $share 'TriggeredTasks') -Recurse -ErrorAction SilentlyContinue
if (-not $tt) { return }
[pscustomobject]@{ TriggeredTaskCount = $tt.Count }
