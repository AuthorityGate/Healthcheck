# Start of Settings
# End of Settings

$Title          = "Clusters Hosting Horizon Workloads"
$Header         = "Per-cluster HA / DRS / EVC summary"
$Comments       = "Only the clusters used by Horizon-registered vCenters are listed. Best practice: HA enabled, DRS Fully Automated (or Partially), EVC enabled."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "95 vSphere Backing Infra"
$Severity       = "P2"
$Recommendation = "Enable HA + DRS on all desktop/RDS clusters. Enable EVC to allow vMotion across CPU generations during agent rolling upgrades."

if (-not $Global:VCConnected) { return }

Get-Cluster -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        Cluster        = $_.Name
        Hosts          = $_.ExtensionData.Host.Count
        HA             = $_.HAEnabled
        AdmissionCtrl  = $_.HAAdmissionControlEnabled
        DRS            = $_.DrsEnabled
        DRSAutomation  = $_.DrsAutomationLevel
        EVCMode        = $_.EVCMode
        VsanEnabled    = $_.VsanEnabled
    }
}

$TableFormat = @{
    HA            = { param($v,$row) if ($v -eq $false) { 'bad' } else { 'ok' } }
    DRS           = { param($v,$row) if ($v -eq $false) { 'warn' } else { 'ok' } }
    EVCMode       = { param($v,$row) if (-not $v) { 'warn' } else { '' } }
}
