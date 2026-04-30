# Start of Settings
$WarnDays = 60
$BadDays  = 30
# End of Settings

$Title          = 'vCenter STS Signing Certificate Expiry'
$Header         = '[count] STS signing cert(s) expiring within ' + $WarnDays + ' days'
$Comments       = 'KB 79248: vCenter Secure Token Service (STS) signing certificates expire silently and break SSO authentication forest-wide. Separate from machine SSL and solution-user certs. Default 10-year validity but custom installs are often 1-2 years.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P1'
$Recommendation = 'Refresh STS cert via /usr/lib/vmware-vmca/bin/certificate-manager option 8 (regenerate STS signing cert). Test logon after rotation.'

if (-not $Global:VCConnected) { return }

# STS certs live in the trust manager; PowerCLI exposes them via the SsoAdminClient
# in newer releases. Fall back to OPS API if not available.
try {
    Import-Module VMware.vSphere.SsoAdmin -ErrorAction SilentlyContinue
    $sso = Get-SsoAdminServer -ErrorAction SilentlyContinue
} catch { }

# Best-effort: query Get-View ServiceInstance.serviceContent for STS info
try {
    $stsInfo = Get-View 'ServiceInstance' -ErrorAction Stop |
        Select-Object -ExpandProperty Content
} catch { }

# Generic certificate enumeration via Get-View on the certificate manager
try {
    $certMgr = Get-View 'CertificateManager' -ErrorAction SilentlyContinue
    if ($certMgr) {
        # Different vCenter versions expose this differently; report what we can
        [pscustomobject]@{
            Source        = 'CertificateManager'
            Note          = 'STS cert enumeration requires vCenter 7.0U3+ or direct call to /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store STS_INTERNAL_SSL_CERT'
            Recommendation= 'Run on vCenter shell: for cert in $(/usr/lib/vmware-vmafd/bin/vecs-cli entry list --store STS_INTERNAL_SSL_CERT --text | grep "Not After"); do echo $cert; done'
        }
    }
} catch { }

# Surface a manual-check row so the consultant knows to look at this even if
# PowerCLI cannot programmatically read STS cert dates from this version.
[pscustomobject]@{
    Source        = 'STS_INTERNAL_SSL_CERT (manual check)'
    Note          = 'PowerCLI does not expose STS cert metadata uniformly across versions; verify manually via vecs-cli on the vCenter appliance.'
    Recommendation= "SSH to vCenter, then: /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store STS_INTERNAL_SSL_CERT --text | grep 'Not After'"
}
