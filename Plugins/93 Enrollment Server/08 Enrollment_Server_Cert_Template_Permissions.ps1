# Start of Settings
# End of Settings

$Title          = 'Enrollment Server Cert Template Permissions'
$Header         = '[count] Enrollment Server(s) - cert template ACL audit needed'
$Comments       = "Each ES uses its computer account to enroll the Enrollment Agent cert. The duplicate 'Smart Card Logon' template (or your custom Horizon EA template) needs Read + Enroll for every ES computer account. We surface every ES + its issuing CA so a CA admin can audit the template ACL on the right CA."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '93 Enrollment Server'
$Severity       = 'P1'
$Recommendation = 'On the issuing CA listed below: certtmpl.msc -> select the EA template -> Properties -> Security tab -> verify the listed ES computer account has Read + Enroll. Remove any over-broad ACL (e.g., Domain Computers).'

if (-not (Get-HVRestSession)) { return }

try { $tsso = Invoke-HVRest -Path '/v1/config/true-sso' -NoPaging } catch { return }
if (-not $tsso) { return }

# Build a CA -> templates lookup if available; otherwise fall back to listing
# the ES + reminding the consultant of the manual audit path.
$caMap = @{}
try {
    $cas = Invoke-HVRest -Path '/v1/config/certificate-authorities' -NoPaging
    foreach ($c in @($cas)) {
        $caMap[$c.id] = $c
    }
} catch { }

foreach ($e in @($tsso.enrollment_servers)) {
    $caName = if ($e.certificate_authority_id -and $caMap.ContainsKey($e.certificate_authority_id)) {
        $caMap[$e.certificate_authority_id].display_name
    } else { '(unknown - run on Horizon Console -> True SSO -> Certificate Authorities)' }

    [pscustomobject]@{
        EnrollmentServer = $e.host_name
        IssuingCA        = $caName
        Status           = $e.status
        Healthy          = if ($null -ne $e.is_healthy) { [bool]$e.is_healthy } else { $false }
        AuditCommand     = "On the issuing CA host: certtmpl.msc - find the EA template, Security tab, verify $($e.host_name) computer account has Read + Enroll"
        Reference        = 'KB 2150772 - True SSO + EA template configuration'
    }
}
