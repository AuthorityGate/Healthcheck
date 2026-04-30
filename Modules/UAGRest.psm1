#Requires -Version 5.1
<#
    UAGRest.psm1
    Thin REST wrapper for Unified Access Gateway (UAG) admin API.
    Default admin port: 9443. Auth: HTTP Basic against /rest/v1/...
    Reference: VMware UAG Admin Guide / docs.omnissa.com
#>

$Script:UAGSession = $null

function Connect-UAGRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][pscredential]$Credential,
        [int]$Port = 9443,
        [switch]$SkipCertificateCheck
    )
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -lt 6) {
        Add-Type -TypeDefinition @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class UAGTrustAll : ICertificatePolicy {
                public bool CheckValidationResult(ServicePoint sp, X509Certificate cert,
                                                   WebRequest req, int problem) { return true; }
            }
"@ -ErrorAction SilentlyContinue
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object UAGTrustAll
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    }

    $base  = "https://$($Server):$Port/rest/v1"
    $pair  = "$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"
    $token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
    # Some UAG builds return 406 when Accept is too narrow. */* accommodates
    # builds that emit XML for /monitor/stats and JSON for /monitor/version.
    $headers = @{ Authorization = "Basic $token"; Accept = '*/*' }

    # Smoke-test the connection. Different UAG builds expose different paths:
    #   - /rest/v1/monitor/stats        (most builds; rejected with 406 on some)
    #   - /rest/v1/monitor/version      (universal since UAG 3.x)
    #   - /rest/v1/system/about         (newer admin UI builds)
    # Try them in order until one returns 200; auth is validated by the first
    # successful call.
    $smokeOK = $false
    $smokeErr = $null
    foreach ($probe in @('/monitor/version','/monitor/stats','/system/about')) {
        $args = @{
            Uri = "$base$probe"
            Headers = $headers
            ErrorAction = 'Stop'
            TimeoutSec = 30
        }
        if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
            $args['SkipCertificateCheck'] = $true
        }
        try { Invoke-RestMethod @args | Out-Null; $smokeOK = $true; break } catch { $smokeErr = $_ }
    }
    if (-not $smokeOK) { throw $smokeErr }

    $Script:UAGSession = [pscustomobject]@{
        Server               = $Server
        BaseUrl              = $base
        Headers              = $headers
        SkipCertificateCheck = [bool]$SkipCertificateCheck
        ConnectedAt          = Get-Date
    }
    $Script:UAGSession
}

function Disconnect-UAGRest {
    [CmdletBinding()]
    param()
    $Script:UAGSession = $null
}

function Get-UAGRestSession { $Script:UAGSession }

function Invoke-UAGRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Get','Post','Put','Delete','Patch')][string]$Method = 'Get',
        $Body
    )
    if (-not $Script:UAGSession) { return $null }
    $args = @{
        Uri         = "$($Script:UAGSession.BaseUrl)$Path"
        Method      = $Method
        Headers     = $Script:UAGSession.Headers
        ContentType = 'application/json'
        ErrorAction = 'Stop'
        TimeoutSec  = 30
    }
    if ($Body) { $args['Body'] = ($Body | ConvertTo-Json -Depth 6) }
    if ($Script:UAGSession.SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $args['SkipCertificateCheck'] = $true
    }
    # Some UAG endpoints 406 on Accept: application/json. Catch and retry
    # with Accept: */* so we widen tolerance without losing JSON parsing
    # (PowerShell auto-deserializes both XML and JSON via Invoke-RestMethod).
    # Endpoints that don't exist on this UAG build return 404 - we return
    # $null so plugins skip gracefully instead of erroring out.
    try {
        Invoke-RestMethod @args
    } catch {
        $code = $null
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        if (-not $code) { try { $code = [int]$_.Exception.StatusCode } catch { } }
        if (-not $code -and $_.Exception.Message -match '\b(\d{3})\b') {
            $cand = [int]$Matches[1]
            if ($cand -ge 400 -and $cand -lt 600) { $code = $cand }
        }
        if ($code -eq 406) {
            $h2 = @{}
            foreach ($k in $Script:UAGSession.Headers.Keys) { $h2[$k] = $Script:UAGSession.Headers[$k] }
            $h2['Accept'] = '*/*'
            $args['Headers'] = $h2
            try { Invoke-RestMethod @args } catch { return $null }
        } elseif ($code -in @(404,405,501)) {
            return $null
        } else { throw }
    }
}

# --- Convenience wrappers (Horizon UAG /rest/v1 API) -----------------------
function Get-UAGSystemSettings    { Invoke-UAGRest -Path '/config/system' }
function Get-UAGEdgeSettings      { Invoke-UAGRest -Path '/config/edgeservice' }
function Get-UAGEdgeServiceList   { Invoke-UAGRest -Path '/config/edgeservice/settings' }
function Get-UAGEdgeViewService   { Invoke-UAGRest -Path '/config/edgeservice/view' }
function Get-UAGEdgeWebReverseProxy { Invoke-UAGRest -Path '/config/edgeservice/webreverseproxy' }
function Get-UAGEdgeTunnelService { Invoke-UAGRest -Path '/config/edgeservice/tunnel' }
function Get-UAGEdgeContentGw     { Invoke-UAGRest -Path '/config/edgeservice/contentgateway' }
function Get-UAGCertificate       { Invoke-UAGRest -Path '/config/certs/ssl/end_user' }
function Get-UAGAdminCertificate  { Invoke-UAGRest -Path '/config/certs/ssl/admin' }
function Get-UAGTrustedCert       { Invoke-UAGRest -Path '/config/certs/trusted' }
function Get-UAGNetworkSettings   { Invoke-UAGRest -Path '/config/system/network' }
function Get-UAGAuthMethod        { Invoke-UAGRest -Path '/config/authmethod' }
function Get-UAGAuthBroker        { Invoke-UAGRest -Path '/config/authbroker' }
function Get-UAGSAMLIdpSettings   { Invoke-UAGRest -Path '/config/authmethod/saml/idp' }
function Get-UAGRADIUSSettings    { Invoke-UAGRest -Path '/config/authmethod/radius' }
function Get-UAGCertAuthSettings  { Invoke-UAGRest -Path '/config/authmethod/cert' }
function Get-UAGRSASecurID        { Invoke-UAGRest -Path '/config/authmethod/securid' }
function Get-UAGSyslogSetting     { Invoke-UAGRest -Path '/config/system/syslog' }
function Get-UAGAdminPolicy       { Invoke-UAGRest -Path '/config/system/adminpolicy' }
function Get-UAGTLSPolicy         { Invoke-UAGRest -Path '/config/system/tlsSyslogServerSettings' }
function Get-UAGSecuritySettings  { Invoke-UAGRest -Path '/config/system/security' }
function Get-UAGUpgradeSetting    { Invoke-UAGRest -Path '/config/system/upgrade' }
function Get-UAGFipsSetting       { Invoke-UAGRest -Path '/config/system/fips' }
function Get-UAGSnmpSetting       { Invoke-UAGRest -Path '/config/system/snmp' }
function Get-UAGEndpointCompliance { Invoke-UAGRest -Path '/config/system/endpointCompliance' }
function Get-UAGSAMLServiceProvider { Invoke-UAGRest -Path '/config/authmethod/saml/sp' }
function Get-UAGOAuthSettings     { Invoke-UAGRest -Path '/config/authmethod/oauth' }
function Get-UAGOcspSetting       { Invoke-UAGRest -Path '/config/system/ocsp' }
function Get-UAGCRLSetting        { Invoke-UAGRest -Path '/config/system/crl' }
function Get-UAGProxyARPSetting   { Invoke-UAGRest -Path '/config/system/proxyarp' }
function Get-UAGTrafficShaping    { Invoke-UAGRest -Path '/config/system/trafficshaping' }
function Get-UAGSshSetting        { Invoke-UAGRest -Path '/config/system/ssh' }
function Get-UAGSessionPersistence { Invoke-UAGRest -Path '/config/system/sessionPersistence' }
function Get-UAGGeoLocation       { Invoke-UAGRest -Path '/config/system/geolocation' }
function Get-UAGOutboundProxy     { Invoke-UAGRest -Path '/config/system/outboundProxy' }
function Get-UAGStaticIPv4Mode    { Invoke-UAGRest -Path '/config/system/network/ipv4Static' }
function Get-UAGNICs              { Invoke-UAGRest -Path '/config/system/network/nics' }
function Get-UAGRoute             { Invoke-UAGRest -Path '/config/system/network/routes' }
function Get-UAGDNS               { Invoke-UAGRest -Path '/config/system/network/dns' }
function Get-UAGNTP               { Invoke-UAGRest -Path '/config/system/network/ntp' }
function Get-UAGMonitorStats      { Invoke-UAGRest -Path '/monitor/stats' }
function Get-UAGSession           { Invoke-UAGRest -Path '/monitor/sessions' }
function Get-UAGVersion           { Invoke-UAGRest -Path '/monitor/version' }
function Get-UAGSystemHealth      { Invoke-UAGRest -Path '/monitor/system' }
function Get-UAGTunnelStats       { Invoke-UAGRest -Path '/monitor/tunnel' }
function Get-UAGBlastStats        { Invoke-UAGRest -Path '/monitor/blast' }
function Get-UAGPCoIPStats        { Invoke-UAGRest -Path '/monitor/pcoip' }
function Get-UAGContentGwStats    { Invoke-UAGRest -Path '/monitor/contentgateway' }
function Get-UAGTunnelSessionDetail { Invoke-UAGRest -Path '/monitor/tunnel/sessions' }
function Get-UAGCertificateExpiry { Invoke-UAGRest -Path '/monitor/certs/expiry' }
function Get-UAGServiceHealth     { Invoke-UAGRest -Path '/monitor/services' }
function Get-UAGCpuStats          { Invoke-UAGRest -Path '/monitor/system/cpu' }
function Get-UAGMemoryStats       { Invoke-UAGRest -Path '/monitor/system/memory' }
function Get-UAGDiskStats         { Invoke-UAGRest -Path '/monitor/system/disk' }
function Get-UAGNetStats          { Invoke-UAGRest -Path '/monitor/system/net' }
function Get-UAGEventLogTail      { Invoke-UAGRest -Path '/monitor/log/recent' }

Export-ModuleMember -Function Connect-UAGRest, Disconnect-UAGRest, Get-UAGRestSession, Invoke-UAGRest, `
    Get-UAG*
