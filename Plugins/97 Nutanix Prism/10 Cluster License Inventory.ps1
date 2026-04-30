# Start of Settings
# End of Settings

$Title          = "Nutanix Cluster License Inventory"
$Header         = "[count] cluster license entitlement(s)"
$Comments       = "Per-cluster Nutanix license type (Starter / Pro / Ultimate / NCI / NCM), count, expiration, and grace state. Critical for upgrade planning - destination AOS / pc.YYYY release may require a feature uplift (e.g., LCM Microservices Platform requires NCM)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "P2"
$Recommendation = "Licenses within 60 days of expiry need renewal initiation now (typical procurement cycle). Mismatch between desired feature (e.g., Flow Networking, Files multi-tier) and license tier blocks the feature."

if (-not (Get-NTNXRestSession)) { return }
$lic = @(Get-NTNXLicense)
if (-not $lic) {
    [pscustomobject]@{ Note='No license info returned (endpoint may require Cluster Admin role).' }
    return
}

foreach ($l in $lic) {
    [pscustomobject]@{
        Cluster         = if ($l.cluster_reference) { $l.cluster_reference.name } else { '' }
        Edition         = $l.edition
        Category        = $l.license_category
        ExpirationDate  = if ($l.expiry_date) { (Get-Date $l.expiry_date).ToString('yyyy-MM-dd') } else { '' }
        DaysToExpiry    = if ($l.expiry_date) { try { [int]((Get-Date $l.expiry_date) - (Get-Date)).TotalDays } catch { '' } } else { '' }
        State           = $l.license_status
        ClusterTier     = $l.cluster_tier
        IsTrial         = [bool]$l.is_trial
    }
}

$TableFormat = @{
    DaysToExpiry = { param($v,$row) if ([int]"$v" -lt 30) { 'bad' } elseif ([int]"$v" -lt 90) { 'warn' } else { '' } }
    State        = { param($v,$row) if ($v -match 'VALID|ACTIVE') { 'ok' } elseif ($v -match 'EXPIR|GRACE') { 'warn' } elseif ($v) { 'bad' } else { '' } }
}
