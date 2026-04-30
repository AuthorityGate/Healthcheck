# Start of Settings
# End of Settings

$Title          = 'App Volumes vCenter Binding'
$Header         = 'App Volumes vCenter integration health'
$Comments       = 'AV manages package attach/detach via vCenter API. Stale credentials = silent attachment failure.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P1'
$Recommendation = 'AV Console -> Settings -> Machine Managers. Re-validate credentials and certificate trust.'

if (-not (Get-AVRestSession)) { return }
try { $ms = Invoke-AVRest -Path '/cv_api/machine_managers' } catch { return }
if (-not $ms) { return }
foreach ($m in $ms.machine_managers) {
    [pscustomobject]@{
        Type     = $m.type
        Host     = $m.host
        Username = $m.username
        Status   = $m.status
    }
}
