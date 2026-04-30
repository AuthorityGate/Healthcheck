#Requires -Version 5.1
<#
    AppVolumesRest.psm1
    Thin REST wrapper for Omnissa / VMware App Volumes Manager.
    API base: https://<av-mgr>/cv_api  (cookie-based session auth)
    Reference: https://developer.omnissa.com/app-volumes/api/  (formerly developer.vmware.com)
#>

$Script:AVSession = $null

function Connect-AVRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][pscredential]$Credential,
        [switch]$SkipCertificateCheck
    )

    $body = @{
        username       = $Credential.UserName
        password       = $Credential.GetNetworkCredential().Password
        domain_name    = ($Credential.UserName -split '\\|@')[0]
    }

    $base = "https://$Server"
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -lt 6) {
        Add-Type -TypeDefinition @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class AVTrustAll : ICertificatePolicy {
                public bool CheckValidationResult(ServicePoint sp, X509Certificate cert,
                                                   WebRequest req, int problem) { return true; }
            }
"@ -ErrorAction SilentlyContinue
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object AVTrustAll
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    }

    $args = @{
        Uri          = "$base/cv_api/sessions"
        Method       = 'Post'
        Body         = $body
        WebSession   = $session
        ErrorAction  = 'Stop'
    }
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $args['SkipCertificateCheck'] = $true
    }
    Invoke-RestMethod @args | Out-Null

    $Script:AVSession = [pscustomobject]@{
        Server               = $Server
        BaseUrl              = $base
        Web                  = $session
        SkipCertificateCheck = [bool]$SkipCertificateCheck
        ConnectedAt          = Get-Date
    }
    $Script:AVSession
}

function Disconnect-AVRest {
    [CmdletBinding()]
    param()
    if (-not $Script:AVSession) { return }
    try {
        $args = @{
            Uri = "$($Script:AVSession.BaseUrl)/cv_api/sessions"
            Method = 'Delete'
            WebSession = $Script:AVSession.Web
            ErrorAction = 'SilentlyContinue'
        }
        if ($Script:AVSession.SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
            $args['SkipCertificateCheck'] = $true
        }
        Invoke-RestMethod @args | Out-Null
    } catch { }
    $Script:AVSession = $null
}

function Get-AVRestSession { $Script:AVSession }

function Invoke-AVRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Get','Post','Put','Delete','Patch')][string]$Method = 'Get',
        $Body
    )
    if (-not $Script:AVSession) { return $null }
    $args = @{
        Uri         = "$($Script:AVSession.BaseUrl)$Path"
        Method      = $Method
        WebSession  = $Script:AVSession.Web
        ContentType = 'application/json'
        ErrorAction = 'Stop'
    }
    if ($Body) { $args['Body'] = ($Body | ConvertTo-Json -Depth 6) }
    if ($Script:AVSession.SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $args['SkipCertificateCheck'] = $true
    }
    Invoke-RestMethod @args
}

# --- Convenience wrappers (App Volumes 4.x REST) ----------------------------
function Get-AVManager           { Invoke-AVRest -Path '/cv_api/managers' }
function Get-AVAppVolume         { Invoke-AVRest -Path '/cv_api/app_products' }
function Get-AVAppPackage        { Invoke-AVRest -Path '/cv_api/app_packages' }
function Get-AVAppMarker         { Invoke-AVRest -Path '/cv_api/app_markers' }
function Get-AVAssignment        { Invoke-AVRest -Path '/cv_api/assignments' }
function Get-AVAttachment        { Invoke-AVRest -Path '/cv_api/attachments' }
function Get-AVDatastore         { Invoke-AVRest -Path '/cv_api/datastores' }
function Get-AVStorageGroup      { Invoke-AVRest -Path '/cv_api/storage_groups' }
function Get-AVMachine           { Invoke-AVRest -Path '/cv_api/machines' }
function Get-AVAdConfig          { Invoke-AVRest -Path '/cv_api/active_directory' }
function Get-AVWritable          { Invoke-AVRest -Path '/cv_api/writables' }
function Get-AVOnlineEntity      { Invoke-AVRest -Path '/cv_api/online_entities' }
function Get-AVAdminGroup        { Invoke-AVRest -Path '/cv_api/admin_groups' }
function Get-AVLicense           { Invoke-AVRest -Path '/cv_api/license' }
function Get-AVServerStatus      { Invoke-AVRest -Path '/cv_api/server_status' }

# --- Expanded coverage (full App Volumes 4.x REST surface) ------------------
function Get-AVOrg               { Invoke-AVRest -Path '/cv_api/org' }
function Get-AVAppStack          { Invoke-AVRest -Path '/cv_api/appstacks' }     # legacy 2.x compat
function Get-AVProgram           { Invoke-AVRest -Path '/cv_api/programs' }
function Get-AVUser              { Invoke-AVRest -Path '/cv_api/users' }
function Get-AVGroup             { Invoke-AVRest -Path '/cv_api/groups' }
function Get-AVOrgUnit           { Invoke-AVRest -Path '/cv_api/org_units' }
function Get-AVComputer          { Invoke-AVRest -Path '/cv_api/computers' }
function Get-AVDirectoryGroup    { Invoke-AVRest -Path '/cv_api/directory/groups' }
function Get-AVDirectoryUser     { Invoke-AVRest -Path '/cv_api/directory/users' }
function Get-AVDirectoryOu       { Invoke-AVRest -Path '/cv_api/directory/org_units' }
function Get-AVAppCapture        { Invoke-AVRest -Path '/cv_api/app_captures' }
function Get-AVStorageLocation   { Invoke-AVRest -Path '/cv_api/storage_locations' }
function Get-AVStorageDest       { Invoke-AVRest -Path '/cv_api/storage_destinations' }
function Get-AVWritableTemplate  { Invoke-AVRest -Path '/cv_api/writable_templates' }
function Get-AVActivity          { Invoke-AVRest -Path '/cv_api/activity_logs' }
function Get-AVActivityRecent    { Invoke-AVRest -Path '/cv_api/activity_logs/recent' }
function Get-AVUserSession       { Invoke-AVRest -Path '/cv_api/user_sessions' }
function Get-AVConfiguration     { Invoke-AVRest -Path '/cv_api/configuration' }
function Get-AVConfigurationSetting { Invoke-AVRest -Path '/cv_api/configuration_settings' }
function Get-AVUploadStorage     { Invoke-AVRest -Path '/cv_api/upload/storage' }
function Get-AVImportTask        { Invoke-AVRest -Path '/cv_api/imports' }
function Get-AVOptInStat         { Invoke-AVRest -Path '/cv_api/opt_in_stats' }
function Get-AVHealthCheckResult { Invoke-AVRest -Path '/cv_api/health_check_results' }
function Get-AVPolicy            { Invoke-AVRest -Path '/cv_api/policies' }
function Get-AVDirectoryServer   { Invoke-AVRest -Path '/cv_api/directory_servers' }
function Get-AVNotification      { Invoke-AVRest -Path '/cv_api/notifications' }
function Get-AVMembership        { Invoke-AVRest -Path '/cv_api/memberships' }
function Get-AVCertificate       { Invoke-AVRest -Path '/cv_api/certificates' }
function Get-AVTLSSetting        { Invoke-AVRest -Path '/cv_api/tls_settings' }
function Get-AVDatabaseInfo      { Invoke-AVRest -Path '/cv_api/database_info' }
function Get-AVManagerHealth     { Invoke-AVRest -Path '/cv_api/manager_health' }
function Get-AVAppCaptureScope   { Invoke-AVRest -Path '/cv_api/app_capture_scopes' }
function Get-AVStorageProvider   { Invoke-AVRest -Path '/cv_api/storage_providers' }
function Get-AVAttachmentRule    { Invoke-AVRest -Path '/cv_api/attachment_rules' }
function Get-AVPackageSyncStatus { Invoke-AVRest -Path '/cv_api/app_packages/sync_status' }
function Get-AVManagerSyncStatus { Invoke-AVRest -Path '/cv_api/managers/sync_status' }
function Get-AVAdSyncStatus      { Invoke-AVRest -Path '/cv_api/active_directory/sync_status' }
function Get-AVDirectoryHealth   { Invoke-AVRest -Path '/cv_api/directory/health' }
function Get-AVAdminAuditLog     { Invoke-AVRest -Path '/cv_api/admin_audit_logs' }
function Get-AVRBACRoles         { Invoke-AVRest -Path '/cv_api/rbac/roles' }
function Get-AVRBACPermission    { Invoke-AVRest -Path '/cv_api/rbac/permissions' }
function Get-AVApplianceVersion  { Invoke-AVRest -Path '/cv_api/version' }
function Get-AVApplianceLicense  { Invoke-AVRest -Path '/cv_api/license/info' }
function Get-AVDeliveryRule      { Invoke-AVRest -Path '/cv_api/delivery_rules' }

Export-ModuleMember -Function Connect-AVRest, Disconnect-AVRest, Get-AVRestSession, Invoke-AVRest, `
    Get-AV*
