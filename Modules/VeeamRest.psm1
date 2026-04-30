#Requires -Version 5.1
<#
    VeeamRest.psm1
    Veeam Backup & Replication REST API wrapper. Available since VBR v11
    at https://<vbr-server>:9419/api/v1/. Auth: OAuth2 password grant.
#>

$Script:VeeamSession = $null

function Connect-VeeamRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][pscredential]$Credential,
        [int]$Port = 9419,
        [switch]$SkipCertificateCheck
    )
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -lt 6) {
        Add-Type -TypeDefinition @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class VeeamTrustAll : ICertificatePolicy {
                public bool CheckValidationResult(ServicePoint sp, X509Certificate cert,
                                                   WebRequest req, int problem) { return true; }
            }
"@ -ErrorAction SilentlyContinue
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object VeeamTrustAll
    }
    $base = "https://${Server}:$Port"
    $body = "grant_type=password&username=$([uri]::EscapeDataString($Credential.UserName))&password=$([uri]::EscapeDataString($Credential.GetNetworkCredential().Password))"
    $args = @{
        Uri         = "$base/api/oauth2/token"
        Method      = 'Post'
        Headers     = @{ 'x-api-version' = '1.1-rev1'; Accept = 'application/json' }
        Body        = $body
        ContentType = 'application/x-www-form-urlencoded'
        ErrorAction = 'Stop'
        TimeoutSec  = 30
    }
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) { $args['SkipCertificateCheck'] = $true }
    $resp = Invoke-RestMethod @args
    if (-not $resp.access_token) { throw "Veeam token grant failed - no access_token in response." }

    $Script:VeeamSession = [pscustomobject]@{
        Server               = $Server
        Port                 = $Port
        BaseUrl              = $base
        Headers              = @{
            Authorization     = "Bearer $($resp.access_token)"
            'x-api-version'   = '1.1-rev1'
            Accept            = 'application/json'
        }
        SkipCertificateCheck = [bool]$SkipCertificateCheck
        ConnectedAt          = Get-Date
    }
    Write-Verbose "Connected to Veeam VBR at ${Server}:$Port"
    $Script:VeeamSession
}
function Disconnect-VeeamRest { $Script:VeeamSession = $null }
function Get-VeeamRestSession { $Script:VeeamSession }

function Invoke-VeeamRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Get','Post','Put','Delete')][string]$Method = 'Get',
        $Body
    )
    if (-not $Script:VeeamSession) { return $null }
    $args = @{
        Uri         = "$($Script:VeeamSession.BaseUrl)$Path"
        Method      = $Method
        Headers     = $Script:VeeamSession.Headers
        ContentType = 'application/json'
        ErrorAction = 'Stop'
        TimeoutSec  = 60
    }
    if ($Body) { $args['Body'] = ($Body | ConvertTo-Json -Depth 10) }
    if ($Script:VeeamSession.SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) { $args['SkipCertificateCheck'] = $true }
    try { Invoke-RestMethod @args }
    catch {
        $code = $null
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        if ($code -in @(401,403,404,405,501)) { return $null }
        throw
    }
}

function Get-VeeamServerInfo       { Invoke-VeeamRest -Path '/api/v1/serverInfo' }
function Get-VeeamJob              { Invoke-VeeamRest -Path '/api/v1/jobs' }
function Get-VeeamJobState         { Invoke-VeeamRest -Path '/api/v1/jobs/states' }
function Get-VeeamLastSession      { Invoke-VeeamRest -Path '/api/v1/sessions?limit=200&orderBy=creationTime&orderAsc=false' }
function Get-VeeamRestorePoint     { Invoke-VeeamRest -Path '/api/v1/restorePoints?limit=200&orderBy=creationTime&orderAsc=false' }
function Get-VeeamProtectedVm      { Invoke-VeeamRest -Path '/api/v1/inventory/vmware/hosts/all/protected' }
function Get-VeeamRepository       { Invoke-VeeamRest -Path '/api/v1/backupInfrastructure/repositories' }
function Get-VeeamRepositoryState  { Invoke-VeeamRest -Path '/api/v1/backupInfrastructure/repositories/states' }
function Get-VeeamProxy            { Invoke-VeeamRest -Path '/api/v1/backupInfrastructure/proxies' }
function Get-VeeamCredential       { Invoke-VeeamRest -Path '/api/v1/credentials' }
function Get-VeeamLicense          { Invoke-VeeamRest -Path '/api/v1/license' }

Export-ModuleMember -Function Connect-VeeamRest, Disconnect-VeeamRest, Get-VeeamRestSession, Invoke-VeeamRest, Get-Veeam*
