# Start of Settings
# End of Settings

$Title          = 'vCenter DRS Rules'
$Header         = '[count] DRS rule(s) defined'
$Comments       = 'DRS rules (VM-VM affinity / anti-affinity / VM-Host) drive placement. Stale rules referencing decommissioned VMs cause DRS to throw warnings.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Audit rules. Remove rules whose member VMs no longer exist.'

if (-not $Global:VCConnected) { return }
# Get-DrsRule requires a -Cluster argument in current PowerCLI; iterate
# every cluster individually. Also pull VM-Host rules (separate cmdlet).
foreach ($c in (Get-Cluster -ErrorAction SilentlyContinue)) {
    foreach ($r in (Get-DrsRule -Cluster $c -ErrorAction SilentlyContinue)) {
        [pscustomobject]@{ Cluster=$c.Name; Name=$r.Name; Type=$r.Type; Enabled=$r.Enabled; Mandatory=$r.Mandatory }
    }
    foreach ($r in (Get-DrsVMHostRule -Cluster $c -ErrorAction SilentlyContinue)) {
        [pscustomobject]@{ Cluster=$c.Name; Name=$r.Name; Type="VMHost-$($r.Type)"; Enabled=$r.Enabled; Mandatory=$r.Mandatory }
    }
}
