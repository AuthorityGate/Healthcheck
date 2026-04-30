# Start of Settings
# End of Settings

$Title          = "vCenter License Inventory"
$Header         = "[count] license key(s) installed in vCenter"
$Comments       = "Every license key on this vCenter, with edition, capacity (CPU sockets / cores / VMs), expiration, and assignment count. Critical for upgrade planning - the destination edition must match or exceed the source's licensed feature set."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "Plan license uplift before upgrading to vSphere 8 if currently on Standard (which does not include vSAN+NSX features)."

if (-not $Global:VCConnected) { return }

$lic = $null
try { $lic = Get-View ServiceInstance | ForEach-Object { Get-View $_.Content.LicenseManager -ErrorAction Stop } } catch { }
if (-not $lic -or -not $lic.Licenses) {
    [pscustomobject]@{ Note = "Unable to read LicenseManager (insufficient privilege)." }
    return
}
foreach ($l in $lic.Licenses) {
    [pscustomobject]@{
        Name        = $l.Name
        Edition     = $l.EditionKey
        Total       = $l.Total
        Used        = $l.Used
        Cost        = $l.CostUnit
        Expires     = ($l.Properties | Where-Object { $_.Key -eq 'expirationDate' }).Value
        LicenseKey  = $l.LicenseKey
        Assignments = $l.Properties | Where-Object { $_.Key -eq 'count' } | ForEach-Object { $_.Value }
    }
}
