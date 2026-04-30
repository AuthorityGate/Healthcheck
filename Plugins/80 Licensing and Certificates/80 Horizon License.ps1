# Start of Settings
# Days-before-expiry threshold to flag.
$LicenseExpiryWarnDays = 60
# End of Settings

$Title          = "Horizon License"
$Header         = "License key, expiry, and feature set"
$Comments       = "Universal subscription licenses generally show 'NEVER' as expiry. Perpetual + subscription dates are reported here."
$Display        = "List"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "80 Licensing and Certificates"
$Severity       = "P1"
$Recommendation = "If expiry is within $LicenseExpiryWarnDays days, raise a renewal request now."

try { $lic = Get-HVLicense } catch { return }
if (-not $lic) { return }

$exp = $lic.expiration_time
$expDate = if ($exp -and $exp -gt 0) { (Get-Date '1970-01-01').AddMilliseconds($exp).ToLocalTime() } else { 'Never' }

[pscustomobject]@{
    'License Edition'      = $lic.license_edition
    'License Mode'         = $lic.license_mode
    'License Key (last5)'  = if ($lic.license_key) { ($lic.license_key -replace '.{0,99}(.....$)','*****$1') } else { '' }
    'Licensed'             = $lic.licensed
    'Usage Model'          = $lic.usage_model
    'Subscription Slice'   = $lic.subscription_slice_expiration_time
    'Expiration'           = $expDate
    'Days To Expiry'       = if ($expDate -is [datetime]) { [int]($expDate - (Get-Date)).TotalDays } else { 'n/a' }
    'Instant Clone'        = $lic.instant_clone_enabled
    'Helpdesk'             = $lic.helpdesk_enabled
    'CPA'                  = $lic.cpa_enabled
    'AppBlast'             = $lic.application_remoting_enabled
    'View Composer'        = $lic.view_composer_enabled
    'SCIM'                 = $lic.scim_enabled
}
