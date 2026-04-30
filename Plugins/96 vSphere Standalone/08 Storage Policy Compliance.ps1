# Start of Settings
# End of Settings

$Title          = "VM Storage Policy Compliance"
$Header         = "[count] VM(s) with storage policy compliance != 'compliant'"
$Comments       = "vSphere reports per-VM compliance with the assigned VM Storage Policy (vSAN FTT, encryption, tag-based placement). 'NotCompliant' on vSAN clusters indicates the object cannot meet its stripe/FTT requirement (commonly: insufficient hosts after a failure)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "VM -> Configure -> Policies -> 'Reapply VM Storage Policy'. If still NotCompliant, check vSAN object placement; you may need to add a host or relax FTT temporarily."

if (-not $Global:VCConnected) { return }

Get-VM -ErrorAction SilentlyContinue | ForEach-Object {
    $vm = $_
    try {
        $pol = Get-SpbmEntityConfiguration -Entity $vm -ErrorAction SilentlyContinue
    } catch { return }
    if (-not $pol) { return }
    if ($pol.ComplianceStatus -and $pol.ComplianceStatus -ne 'compliant') {
        [pscustomobject]@{
            VM         = $vm.Name
            Policy     = $pol.StoragePolicy.Name
            Status     = $pol.ComplianceStatus
            LastChecked = $pol.TimeOfCheck
        }
    }
}

$TableFormat = @{ Status = { param($v,$row) 'warn' } }
