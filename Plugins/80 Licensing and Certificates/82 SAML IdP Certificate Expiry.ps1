# Start of Settings
# End of Settings

$Title          = 'SAML IdP Metadata Currency'
$Header         = 'SAML 2.0 metadata refresh status'
$Comments       = 'IdP signing-certificate rotation forces metadata refresh; expired metadata == silent SSO failure.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '80 Licensing and Certificates'
$Severity       = 'P2'
$Recommendation = "Re-import IdP metadata from the canonical URL. Verify cert thumbprint matches IdP's current cert."

if (-not (Get-HVRestSession)) { return }
try { $sa = Invoke-HVRest -Path '/v1/config/saml-authenticators' } catch { return }
if (-not $sa) { return }
foreach ($s in $sa) {
    $stale = $false
    if ($s.metadata_refresh_time) {
        $age = (New-TimeSpan -Start (Get-Date '1970-01-01').AddMilliseconds($s.metadata_refresh_time).ToLocalTime() -End (Get-Date)).TotalDays
        if ($age -gt 30) { $stale = $true }
    }
    [pscustomobject]@{
        Authenticator       = $s.label
        StaticMetadataUrl   = $s.static_metadata_url
        DynamicMetadataUrl  = $s.dynamic_metadata_url
        LastMetadataRefresh = if ($s.metadata_refresh_time) { (Get-Date '1970-01-01').AddMilliseconds($s.metadata_refresh_time).ToLocalTime() } else { 'never' }
        StaleMetadata       = $stale
    }
}

