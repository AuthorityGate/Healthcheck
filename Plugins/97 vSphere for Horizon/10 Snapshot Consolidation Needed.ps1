# Start of Settings
# End of Settings

$Title          = "VMs Requiring Snapshot Consolidation"
$Header         = "[count] VM(s) flagged with 'Consolidation Needed'"
$Comments       = "VMware KB 1003302 / 1002310: VMs with consolidation flag are running on residual delta files after a failed snapshot delete. They consume extra storage, slow boot, and can corrupt during snapshot revert. Common in Horizon environments after failed Composer / instant-clone push-image jobs."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P2"
$Recommendation = "Right-click VM -> Snapshots -> 'Consolidate'. If consolidation fails, see KB 2003638 (orphaned snapshot disk locks)."

if (-not $Global:VCConnected) { return }

Get-VM -ErrorAction SilentlyContinue | Where-Object {
    $_.ExtensionData.Runtime.ConsolidationNeeded
} | ForEach-Object {
    [pscustomobject]@{
        VM           = $_.Name
        PowerState   = $_.PowerState
        ProvisionedGB = [math]::Round($_.ProvisionedSpaceGB,1)
        UsedGB       = [math]::Round($_.UsedSpaceGB,1)
        Cluster      = $_.VMHost.Parent.Name
    }
}

$TableFormat = @{ VM = { param($v,$row) 'warn' } }
