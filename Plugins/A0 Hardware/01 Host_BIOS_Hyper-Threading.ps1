# Start of Settings
# End of Settings

$Title          = 'Host BIOS Hyper-Threading'
$Header         = 'Host hyper-threading enable state'
$Comments       = 'Disabling HT halves logical cores. Required disabled only for L1TF mitigations on workloads where HT cross-talk is a risk.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'A0 Hardware'
$Severity       = 'Info'
$Recommendation = 'Default: HT enabled. If disabled, document the L1TF compliance reason.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        Host         = $_.Name
        HyperThreading = $_.HyperthreadingActive
        LogicalCpu   = $_.NumCpu
    }
}
