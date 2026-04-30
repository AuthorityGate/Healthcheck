#Requires -Version 5.1
<#
    UEMRest.psm1
    Workspace ONE UEM (formerly AirWatch) REST wrapper.

    Auth model: Basic auth (admin user + password) PLUS the API key in the
    'aw-tenant-code' header. Some 2306+ tenants also support OAuth, but
    Basic + tenant code is the universal mode and what we target.

    Reference: docs.omnissa.com / docs.vmware.com Workspace ONE UEM REST
    API guide. Default tenant API path: /api. Most reads use Accept:
    application/json (some legacy endpoints emit XML by default).
#>

$Script:UEMSession = $null

function Connect-UEMRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)][string]$ApiKey,
        [int]$Port = 443,
        [switch]$SkipCertificateCheck
    )

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -lt 6) {
        Add-Type -TypeDefinition @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class UEMTrustAll : ICertificatePolicy {
                public bool CheckValidationResult(ServicePoint sp, X509Certificate cert,
                                                   WebRequest req, int problem) { return true; }
            }
"@ -ErrorAction SilentlyContinue
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object UEMTrustAll
    }

    $base = "https://${Server}:$Port"
    $pair = "$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"
    $authHdr = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
    $headers = @{
        Authorization     = $authHdr
        'aw-tenant-code'  = $ApiKey
        Accept            = 'application/json;version=2'
    }

    # Smoke test via /api/system/info
    $args = @{
        Uri         = "$base/api/system/info"
        Method      = 'Get'
        Headers     = $headers
        ContentType = 'application/json'
        ErrorAction = 'Stop'
        TimeoutSec  = 30
    }
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $args['SkipCertificateCheck'] = $true
    }
    $info = Invoke-RestMethod @args

    $Script:UEMSession = [pscustomobject]@{
        Server               = $Server
        Port                 = $Port
        BaseUrl              = $base
        Credential           = $Credential
        ApiKey               = $ApiKey
        Headers              = $headers
        SystemInfo           = $info
        SkipCertificateCheck = [bool]$SkipCertificateCheck
        ConnectedAt          = Get-Date
    }
    Write-Verbose "Connected to UEM at ${Server}:$Port"
    $Script:UEMSession
}

function Disconnect-UEMRest { $Script:UEMSession = $null }

function Get-UEMRestSession { $Script:UEMSession }

function Invoke-UEMRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Get','Post','Put','Delete')][string]$Method = 'Get',
        $Body,
        [string]$AcceptOverride
    )
    if (-not $Script:UEMSession) { return $null }
    $h = @{}
    foreach ($k in $Script:UEMSession.Headers.Keys) { $h[$k] = $Script:UEMSession.Headers[$k] }
    if ($AcceptOverride) { $h['Accept'] = $AcceptOverride }
    $args = @{
        Uri         = "$($Script:UEMSession.BaseUrl)$Path"
        Method      = $Method
        Headers     = $h
        ContentType = 'application/json'
        ErrorAction = 'Stop'
        TimeoutSec  = 60
    }
    if ($Body) { $args['Body'] = ($Body | ConvertTo-Json -Depth 10) }
    if ($Script:UEMSession.SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $args['SkipCertificateCheck'] = $true
    }
    try { Invoke-RestMethod @args }
    catch {
        $code = $null
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        if (-not $code) { try { $code = [int]$_.Exception.StatusCode } catch { } }
        # 406 retry: some endpoints reject json;version=2 - retry json plain
        if ($code -eq 406) {
            $h['Accept'] = 'application/json'
            $args['Headers'] = $h
            try { return Invoke-RestMethod @args } catch { }
        }
        if ($code -in @(401,403,404,405,406,501)) { return $null }
        throw
    }
}

# --- Endpoint wrappers ------------------------------------------------------
function Get-UEMSystemInfo            { Invoke-UEMRest -Path '/api/system/info' }
function Get-UEMOrganizationGroup     { Invoke-UEMRest -Path '/api/system/groups/search' }
function Get-UEMUser                  { Invoke-UEMRest -Path '/api/system/users/search' }
function Get-UEMUserGroup             { Invoke-UEMRest -Path '/api/system/usergroups/search' }
function Get-UEMAdmin                 { Invoke-UEMRest -Path '/api/system/admins/search' }
function Get-UEMDevice                { Invoke-UEMRest -Path '/api/mdm/devices/search' }
function Get-UEMDeviceCount {
    # Lightweight count probe for the Device Inventory plugin.
    Invoke-UEMRest -Path '/api/mdm/devices/search?pagesize=1'
}
function Get-UEMSmartGroup            { Invoke-UEMRest -Path '/api/mdm/smartgroups/search' }
function Get-UEMProfile               { Invoke-UEMRest -Path '/api/mdm/profiles/search' }
function Get-UEMDevicePolicy          { Invoke-UEMRest -Path '/api/mdm/devicepolicies/search' }
function Get-UEMApplication           { Invoke-UEMRest -Path '/api/mam/apps/search' }
function Get-UEMInternalApplication   { Invoke-UEMRest -Path '/api/mam/apps/internal/search' }
function Get-UEMPublicApplication     { Invoke-UEMRest -Path '/api/mam/apps/public/search' }
function Get-UEMPurchasedApplication  { Invoke-UEMRest -Path '/api/mam/apps/purchased/search' }
function Get-UEMComplianceProfile     { Invoke-UEMRest -Path '/api/mdm/compliance/search' }
function Get-UEMCompliancePolicy      { Invoke-UEMRest -Path '/api/mdm/compliancepolicies/search' }
function Get-UEMTagInventory          { Invoke-UEMRest -Path '/api/mdm/tags/search' }
function Get-UEMDepProfile            { Invoke-UEMRest -Path '/api/mdm/dep/profiles' }
function Get-UEMRoleAssignment        { Invoke-UEMRest -Path '/api/system/roles/search' }
function Get-UEMRecentEnrollment      { Invoke-UEMRest -Path '/api/mdm/devices/search?orderby=lastenrolledon&pagesize=50' }

Export-ModuleMember -Function Connect-UEMRest, Disconnect-UEMRest, Get-UEMRestSession, Invoke-UEMRest, `
    Get-UEM*
