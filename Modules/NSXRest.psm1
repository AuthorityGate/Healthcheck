#Requires -Version 5.1
<#
    NSXRest.psm1
    Thin REST wrapper for NSX-T / NSX (3.x / 4.x). Auth: HTTP Basic.
    API base: https://<nsx-mgr>/api/v1   (Management plane API)
    Policy API base: /policy/api/v1      (Declarative policy API)
    Reference: https://developer.broadcom.com/xapis/nsx-t-data-center-rest-api/latest/
#>

$Script:NSXSession = $null

function Connect-NSXRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][pscredential]$Credential,
        [switch]$SkipCertificateCheck
    )
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -lt 6) {
        Add-Type -TypeDefinition @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class NSXTrustAll : ICertificatePolicy {
                public bool CheckValidationResult(ServicePoint sp, X509Certificate cert,
                                                   WebRequest req, int problem) { return true; }
            }
"@ -ErrorAction SilentlyContinue
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object NSXTrustAll
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    }

    $base  = "https://$Server"
    $pair  = "$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"
    $token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
    $headers = @{ Authorization = "Basic $token"; Accept = 'application/json' }

    # Smoke-test
    $args = @{
        Uri = "$base/api/v1/node"
        Headers = $headers
        ErrorAction = 'Stop'
    }
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $args['SkipCertificateCheck'] = $true
    }
    Invoke-RestMethod @args | Out-Null

    $Script:NSXSession = [pscustomobject]@{
        Server               = $Server
        BaseUrl              = $base
        Headers              = $headers
        SkipCertificateCheck = [bool]$SkipCertificateCheck
        ConnectedAt          = Get-Date
    }
    $Script:NSXSession
}

function Disconnect-NSXRest {
    [CmdletBinding()]
    param()
    $Script:NSXSession = $null
}

function Get-NSXRestSession { $Script:NSXSession }

function Invoke-NSXRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Get','Post','Put','Delete','Patch')][string]$Method = 'Get',
        $Body
    )
    if (-not $Script:NSXSession) { return $null }
    $args = @{
        Uri         = "$($Script:NSXSession.BaseUrl)$Path"
        Method      = $Method
        Headers     = $Script:NSXSession.Headers
        ContentType = 'application/json'
        ErrorAction = 'Stop'
    }
    if ($Body) { $args['Body'] = ($Body | ConvertTo-Json -Depth 8) }
    if ($Script:NSXSession.SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $args['SkipCertificateCheck'] = $true
    }
    $resp = Invoke-RestMethod @args
    # NSX wraps lists in a 'results' property
    if ($resp.PSObject.Properties.Name -contains 'results' -and $Method -eq 'Get') {
        return $resp.results
    }
    $resp
}

# --- Management API wrappers ------------------------------------------------
function Get-NSXNode                 { Invoke-NSXRest -Path '/api/v1/node' }
function Get-NSXClusterStatus        { Invoke-NSXRest -Path '/api/v1/cluster/status' }
function Get-NSXClusterNode          { Invoke-NSXRest -Path '/api/v1/cluster/nodes' }
function Get-NSXEdgeCluster          { Invoke-NSXRest -Path '/api/v1/edge-clusters' }
function Get-NSXTransportNode        { Invoke-NSXRest -Path '/api/v1/transport-nodes' }
function Get-NSXTransportZone        { Invoke-NSXRest -Path '/api/v1/transport-zones' }
function Get-NSXLogicalSwitch        { Invoke-NSXRest -Path '/api/v1/logical-switches' }
function Get-NSXLogicalRouter        { Invoke-NSXRest -Path '/api/v1/logical-routers' }
function Get-NSXFirewallSection      { Invoke-NSXRest -Path '/api/v1/firewall/sections' }
function Get-NSXComputeManager       { Invoke-NSXRest -Path '/api/v1/fabric/compute-managers' }
function Get-NSXBackupConfig         { Invoke-NSXRest -Path '/api/v1/cluster/backups/config' }
function Get-NSXBackupHistory        { Invoke-NSXRest -Path '/api/v1/cluster/backups/history' }
function Get-NSXTrustObject          { Invoke-NSXRest -Path '/api/v1/trust-management/certificates' }
function Get-NSXAlarm                { Invoke-NSXRest -Path '/api/v1/alarms?status=OPEN' }
function Get-NSXTier1                { Invoke-NSXRest -Path '/policy/api/v1/infra/tier-1s' }
function Get-NSXTier0                { Invoke-NSXRest -Path '/policy/api/v1/infra/tier-0s' }
function Get-NSXSegment              { Invoke-NSXRest -Path '/policy/api/v1/infra/segments' }
function Get-NSXDfwPolicy            { Invoke-NSXRest -Path '/policy/api/v1/infra/domains/default/security-policies' }
function Get-NSXLoadBalancer         { Invoke-NSXRest -Path '/policy/api/v1/infra/lb-services' }
function Get-NSXVpnIpsec             { Invoke-NSXRest -Path '/policy/api/v1/infra/tier-0s/default/locale-services/default/ipsec-vpn-services' }

Export-ModuleMember -Function Connect-NSXRest, Disconnect-NSXRest, Get-NSXRestSession, Invoke-NSXRest, `
    Get-NSXNode, Get-NSXClusterStatus, Get-NSXClusterNode, Get-NSXEdgeCluster, Get-NSXTransportNode, `
    Get-NSXTransportZone, Get-NSXLogicalSwitch, Get-NSXLogicalRouter, Get-NSXFirewallSection, `
    Get-NSXComputeManager, Get-NSXBackupConfig, Get-NSXBackupHistory, Get-NSXTrustObject, `
    Get-NSXAlarm, Get-NSXTier1, Get-NSXTier0, Get-NSXSegment, Get-NSXDfwPolicy, `
    Get-NSXLoadBalancer, Get-NSXVpnIpsec
