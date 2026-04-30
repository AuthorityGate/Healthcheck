# Start of Settings
# End of Settings

$Title          = "UEM Compliance Policies"
$Header         = "[count] compliance policy(ies) defined"
$Comments       = "Each compliance policy is a (rule, action, escalation) triple - e.g., 'if encryption disabled then warn for 24h, then mark non-compliant, then push remediation profile'. Inventory of every defined policy with its current device-impact count."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B6 Workspace ONE UEM"
$Severity       = "P2"
$Recommendation = "Policies with > 0 non-compliant devices need triage. Stale / disabled policies cluttering the list can be archived. Every production OG should have at least one Active compliance policy attached."

if (-not (Get-UEMRestSession)) { return }
$resp = Get-UEMCompliancePolicy
if (-not $resp -or -not $resp.Policies) {
    # Fallback to legacy compliance endpoint
    $resp = Get-UEMComplianceProfile
}
if (-not $resp -or -not ($resp.Policies -or $resp.Profiles)) {
    [pscustomobject]@{ Note = 'No compliance policies returned. Older UEM versions expose this differently - confirm via the UEM Console UI.' }
    return
}

$items = if ($resp.Policies) { $resp.Policies } else { $resp.Profiles }
foreach ($p in $items) {
    [pscustomobject]@{
        Name             = if ($p.Name) { $p.Name } else { $p.PolicyName }
        Status           = $p.Status
        Platform         = $p.Platform
        OG               = $p.OrganizationGroupName
        DevicesAssigned  = $p.AssignedDeviceCount
        DevicesCompliant = $p.CompliantDeviceCount
        DevicesNonCompliant = $p.NonCompliantDeviceCount
        LastModified     = $p.LastModifiedOn
    }
}

$TableFormat = @{
    Status = { param($v,$row) if ($v -eq 'Active') { 'ok' } elseif ($v -eq 'Inactive') { 'warn' } else { '' } }
    DevicesNonCompliant = { param($v,$row) if ([int]"$v" -gt 0) { 'warn' } else { 'ok' } }
}
