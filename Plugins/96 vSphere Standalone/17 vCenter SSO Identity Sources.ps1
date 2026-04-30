# Start of Settings
# End of Settings

$Title          = "vCenter SSO Identity Sources"
$Header         = "vCenter SSO identity-source inventory"
$Comments       = "Reference: vCenter Server Admin Guide. Healthy SSO has 1 'Local OS' (vmdir), 1 'System' (vsphere.local), and at least one 'Active Directory over LDAP' / 'AD-IWA' source. Multiple stale AD-IWA bindings are a common cause of slow vCenter Console login."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "Info"
$Recommendation = "Trim unused identity sources via the vSphere Client -> Administration -> Single Sign On -> Configuration. Use AD over LDAPS (not deprecated AD-IWA) for new bindings."

if (-not $Global:VCConnected) { return }
$vc = $global:DefaultVIServer
if (-not $vc) { return }

# SSO config is exposed under the AdminService for vCenter API; surface what we can read via VimClient
try {
    $ssoSvc = Get-View -Id 'SsoAdminIdentitySources' -ErrorAction SilentlyContinue
    if (-not $ssoSvc) { return }
    foreach ($src in @($ssoSvc.LocalOS) + @($ssoSvc.System) + @($ssoSvc.LDAPs) + @($ssoSvc.NIS)) {
        if (-not $src) { continue }
        [pscustomobject]@{
            Type        = $src.GetType().Name -replace '.*\.',''
            Name        = $src.Name
            Domain      = $src.DomainName
            Alias       = $src.Alias
            AuthType    = $src.AuthenticationType
        }
    }
} catch {
    # SSO admin client not available - surface a minimal advisory row so the user knows the check ran
    [pscustomobject]@{
        Type   = 'n/a'
        Name   = 'SSO admin API not reachable from this PowerShell session'
        Domain = ''
        Alias  = ''
        AuthType = 'Run vSphere Client -> Administration -> Single Sign On -> Identity Sources to verify manually.'
    }
}
