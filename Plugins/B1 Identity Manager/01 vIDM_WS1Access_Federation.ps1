# Start of Settings
# End of Settings

$Title          = 'vIDM / Workspace ONE Access Federation'
$Header         = "[count] SAML 2.0 IdP federation entry point(s) configured in Horizon"
$Comments       = "Horizon SAML federation to VMware Identity Manager (vIDM) / Workspace ONE Access lets the IdP terminate user authentication and pass an assertion to Horizon. Surfaces every configured SAML authenticator, its metadata source URL, signing cert expiry, and Horizon-side trust state."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'B1 Identity Manager'
$Severity       = 'P1'
$Recommendation = "If an IdP is configured but auto-refresh metadata is OFF, schedule manual refresh before any IdP cert rotation. If metadata signing cert expires within 60 days, plan refresh now. Validate test logon via the IdP path monthly."

if (-not (Get-HVRestSession)) { return }

try { $list = Invoke-HVRest -Path '/v1/config/saml-authenticators' -NoPaging } catch { return }
if (-not $list -or @($list).Count -eq 0) { return }

foreach ($a in @($list)) {
    $expiry = if ($a.metadata_signing_certificate_expiration) {
        try { ([datetime]$a.metadata_signing_certificate_expiration).ToString('yyyy-MM-dd') } catch { '' }
    } else { '' }
    $daysLeft = if ($a.metadata_signing_certificate_expiration) {
        try { [int]([datetime]$a.metadata_signing_certificate_expiration - (Get-Date)).TotalDays } catch { $null }
    } else { $null }

    [pscustomobject]@{
        Authenticator       = $a.label
        Type                = $a.type
        MetadataSource      = $a.metadata_source
        MetadataSourceUrl   = $a.metadata_source_url
        AutoRefreshMeta     = $a.metadata_source_auto_refresh
        StaticEntityId      = $a.static_entity_id
        AcsEndpoint         = $a.acs_endpoint
        SigningCertExpiry   = $expiry
        DaysToExpiry        = $daysLeft
        Status              = $a.status
    }
}

$TableFormat = @{
    DaysToExpiry      = { param($v,$row) if ($v -ne $null -and $v -lt 60) { 'bad' } elseif ($v -ne $null -and $v -lt 90) { 'warn' } else { '' } }
    AutoRefreshMeta   = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
    Status            = { param($v,$row) if ($v -ne 'OK' -and $v -ne 'CONNECTED') { 'warn' } else { '' } }
}
