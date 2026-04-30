# Start of Settings
# End of Settings

$Title          = "Nutanix LCM Firmware + Software Currency"
$Header         = "Lifecycle Manager update inventory"
$Comments       = "Reads the LCM (Life Cycle Manager) entity inventory: per-host BIOS, BMC, NIC firmware, AOS, hypervisor, NCC, Foundation, Calm, Move. Surfaces components that have an available update. Out-of-date BMC / BIOS = CVE exposure; out-of-date AOS = bug risk."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "P2"
$Recommendation = "LCM updates should be scheduled monthly or quarterly with proper change-control. Components flagged 'available_update' have a vendor-released newer version. Run 'LCM Inventory' in Prism if 'last inventory' is stale."

if (-not (Get-NTNXRestSession)) { return }
$lcm = $null
try { $lcm = Get-NTNXLcmEntity } catch { }
if (-not $lcm) {
    [pscustomobject]@{ Note='LCM endpoint not exposed (older AOS or insufficient role). Run "LCM Inventory" in Prism UI then re-run.' }
    return
}
$entities = if ($lcm.entities) { @($lcm.entities) } else { @($lcm) }
if ($entities.Count -eq 0) {
    [pscustomobject]@{ Note = 'LCM returned no entities. Run an LCM inventory first.' }
    return
}

foreach ($e in $entities) {
    [pscustomobject]@{
        Component       = $e.entity_class
        Model           = $e.entity_model
        CurrentVersion  = $e.entity_version
        AvailableUpdate = if ($e.available_versions) { ($e.available_versions | Select-Object -First 1) } else { '' }
        Cluster         = if ($e.cluster_name) { $e.cluster_name } else { '' }
        UpdateAvailable = [bool]$e.available_versions
    }
}

$TableFormat = @{
    UpdateAvailable = { param($v,$row) if ($v -eq $true) { 'warn' } elseif ($v -eq $false) { 'ok' } else { '' } }
}
