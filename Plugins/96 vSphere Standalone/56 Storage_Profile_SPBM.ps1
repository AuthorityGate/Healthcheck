# Start of Settings
# End of Settings

$Title          = 'VM Storage Policy (SPBM) Inventory'
$Header         = "[count] VM(s) with non-default or compliance issues"
$Comments       = "Each VM has an assigned Storage Profile (SPBM). Without explicit assignment, VMs use 'Datastore Default' which provides no FTT guarantee. Compliance issues = VM not meeting policy + at risk."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = "Production VMs should have explicit storage policies. Review 'Out of Compliance' VMs - they may not be at the FTT level expected."

if (-not $Global:VCConnected) { return }

try {
    Get-VM -ErrorAction SilentlyContinue | ForEach-Object {
        $vm = $_
        try {
            $compliance = Get-SpbmEntityConfiguration -VM $vm -ErrorAction SilentlyContinue
            if ($compliance -and $compliance.ComplianceStatus -ne 'compliant') {
                [pscustomobject]@{
                    VM       = $vm.Name
                    Cluster  = if ($vm.VMHost -and $vm.VMHost.Parent) { $vm.VMHost.Parent.Name } else { '' }
                    Policy   = if ($compliance.StoragePolicy) { $compliance.StoragePolicy.Name } else { '(none)' }
                    Compliance = $compliance.ComplianceStatus
                    Note     = if ($compliance.ComplianceStatus -eq 'nonCompliant') { 'NOT meeting storage policy' } else { '' }
                }
            }
        } catch { }
    }
} catch { }

$TableFormat = @{
    Compliance = { param($v,$row) if ($v -eq 'nonCompliant') { 'bad' } elseif ($v -eq 'unknown') { 'warn' } else { '' } }
}
