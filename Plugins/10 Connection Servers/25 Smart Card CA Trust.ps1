# Start of Settings
# End of Settings

$Title          = 'Smart Card CA Trust List'
$Header         = '[count] CA(s) trusted for smart-card authentication'
$Comments       = "Reference: Horizon Admin Guide -> 'Smart Card Authentication'. The CS keystore must contain the issuing CA chain for any smart card to be accepted."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'P2'
$Recommendation = "Re-import the CA chain (rootcert + intermediates) into the CS Java keystore via 'sviconfig.exe' if any required CA is missing."

if (-not (Get-HVRestSession)) { return }
try { $sc = Invoke-HVRest -Path '/v1/config/cert-sso' -NoPaging } catch { return }
if (-not $sc) { return }
[pscustomobject]@{
    Enabled               = $sc.enabled
    AllowSmartCardLogon   = $sc.allow_smart_card_logon
    EnforceSCLogonForRdsh = $sc.enforce_smart_card_logon_for_rdsh
    OcspEnabled           = $sc.use_ocsp
    UseOcspCrl            = $sc.use_crl_when_ocsp_fails
}

