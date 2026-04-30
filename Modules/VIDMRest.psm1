#Requires -Version 5.1
<#
    VIDMRest.psm1
    Workspace ONE Access (vIDM / IDM) REST wrapper.
    Auth: OAuth client credentials grant - Client ID + Shared Secret get a
    bearer token. Most enterprise deployments enable a 'remote app access'
    OAuth client for automation; this module assumes that token-issuance
    workflow is in place. As fallback, the same module accepts a domain
    bearer token if the operator already has one.

    Reference: docs.omnissa.com / docs.vmware.com Workspace ONE Access
    REST API guide. v23.09+ tested; older 21.x / 22.x mostly compatible.
#>

$Script:VIDMSession = $null

function Connect-VIDMRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory, ParameterSetName='ClientCred')][string]$ClientId,
        [Parameter(Mandatory, ParameterSetName='ClientCred')][string]$ClientSecret,
        [Parameter(Mandatory, ParameterSetName='Bearer')][string]$BearerToken,
        [string]$TenantPath = '/SAAS',
        [int]$Port = 443,
        [switch]$SkipCertificateCheck
    )

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -lt 6) {
        Add-Type -TypeDefinition @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class VIDMTrustAll : ICertificatePolicy {
                public bool CheckValidationResult(ServicePoint sp, X509Certificate cert,
                                                   WebRequest req, int problem) { return true; }
            }
"@ -ErrorAction SilentlyContinue
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object VIDMTrustAll
    }

    $base = "https://${Server}:$Port"
    $token = $null

    if ($PSCmdlet.ParameterSetName -eq 'Bearer') {
        $token = $BearerToken
    } else {
        # OAuth client_credentials grant. The token endpoint at vIDM is
        # /SAAS/auth/oauthtoken (with the SAAS tenant path).
        $tokenUrl = "$base$TenantPath/auth/oauthtoken"
        $pair = "${ClientId}:${ClientSecret}"
        $authHdr = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
        $body = 'grant_type=client_credentials'
        $args = @{
            Uri = $tokenUrl
            Method = 'Post'
            Headers = @{ Authorization = $authHdr; Accept = 'application/json' }
            Body = $body
            ContentType = 'application/x-www-form-urlencoded'
            ErrorAction = 'Stop'
            TimeoutSec = 30
        }
        if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) { $args['SkipCertificateCheck'] = $true }
        $resp = Invoke-RestMethod @args
        if (-not $resp.access_token) { throw "vIDM token grant returned no access_token. Verify the OAuth client has 'Admin' scope and grant_type=client_credentials is enabled." }
        $token = $resp.access_token
    }

    $Script:VIDMSession = [pscustomobject]@{
        Server               = $Server
        Port                 = $Port
        TenantPath           = $TenantPath
        BaseUrl              = $base
        BearerToken          = $token
        Headers              = @{
            Authorization = "HZN $token"
            Accept        = 'application/json'
        }
        SkipCertificateCheck = [bool]$SkipCertificateCheck
        ConnectedAt          = Get-Date
    }
    Write-Verbose "Connected to vIDM at ${Server}:$Port"
    $Script:VIDMSession
}

function Disconnect-VIDMRest { $Script:VIDMSession = $null }

function Get-VIDMRestSession { $Script:VIDMSession }

function Invoke-VIDMRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Get','Post','Put','Delete')][string]$Method = 'Get',
        $Body
    )
    if (-not $Script:VIDMSession) { return $null }
    $args = @{
        Uri         = "$($Script:VIDMSession.BaseUrl)$Path"
        Method      = $Method
        Headers     = $Script:VIDMSession.Headers
        ContentType = 'application/json'
        ErrorAction = 'Stop'
        TimeoutSec  = 60
    }
    if ($Body) { $args['Body'] = ($Body | ConvertTo-Json -Depth 8) }
    if ($Script:VIDMSession.SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $args['SkipCertificateCheck'] = $true
    }
    try { Invoke-RestMethod @args }
    catch {
        $code = $null
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        if (-not $code) { try { $code = [int]$_.Exception.StatusCode } catch { } }
        if ($code -in @(401,403,404,405,501)) { return $null }
        throw
    }
}

# --- Endpoint wrappers (vIDM v23+ paths) ----------------------------------
function Get-VIDMSystemInfo       { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/system/info' }
function Get-VIDMHealth           { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/system/health/check' }
function Get-VIDMConnector        { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/connectors' }
function Get-VIDMDirectory        { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/directories' }
function Get-VIDMScimUser         { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/scim/Users' }
function Get-VIDMScimGroup        { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/scim/Groups' }
function Get-VIDMApplication      { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/catalogitems/search' }
function Get-VIDMAccessPolicy     { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/accessPolicies' }
function Get-VIDMAuthPolicy       { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/idprules' }
function Get-VIDMTenantConfig     { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/tenants' }
function Get-VIDMRecentEvent      { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/notification/events?count=200' }
function Get-VIDMAdmin            { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/admins' }
function Get-VIDMAuthMethod       { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/authmethods' }
function Get-VIDMSamlMetadata     { Invoke-VIDMRest -Path '/SAAS/API/1.0/GET/metadata/idp.xml' }
function Get-VIDMHubServiceConfig { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/hubservice/configuration' }
function Get-VIDMRoles            { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/roles' }
function Get-VIDMNamedUserGroup   { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/namedUserGroups' }
function Get-VIDMNotification     { Invoke-VIDMRest -Path '/SAAS/jersey/manager/api/notifications' }

Export-ModuleMember -Function Connect-VIDMRest, Disconnect-VIDMRest, Get-VIDMRestSession, Invoke-VIDMRest, `
    Get-VIDM*
