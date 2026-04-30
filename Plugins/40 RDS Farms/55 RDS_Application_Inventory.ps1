# Start of Settings
# End of Settings

$Title          = 'RDS Application Inventory'
$Header         = "[count] RemoteApp(s) published"
$Comments       = "Apps published from RDSH farms. Inventory shows what's delivered + which farm + entitlement scope. Stale apps = clutter; un-entitled = capacity waste."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '40 RDS Farms'
$Severity       = 'Info'
$Recommendation = "Audit published apps annually. Decommission unused. Verify entitlement matches business owner."

if (-not (Get-HVRestSession)) { return }

try { $apps = Get-HVApplicationPool -ErrorAction SilentlyContinue } catch { return }
if (-not $apps) { return }

foreach ($a in $apps) {
    [pscustomobject]@{
        Application   = $a.display_name
        Farm          = $a.farm_id
        Path          = $a.executable_path
        Version       = $a.application_version
        Publisher     = $a.publisher
        Enabled       = $a.enabled
        AntiAffinity  = if ($a.anti_affinity_patterns) { ($a.anti_affinity_patterns -join ',') } else { '' }
    }
}

$TableFormat = @{
    Enabled = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
}
