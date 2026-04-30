# Start of Settings
# End of Settings

$Title          = "Registered vCenter Servers"
$Header         = "[count] vCenter(s) registered with Horizon"
$Comments       = "Includes the View Composer linkage (legacy) where present, certificate state, and session limits."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "10 Connection Servers"
$Severity       = "Info"
$Recommendation = "Replace any vCenters whose certificate is invalid; verify session/operation limits match the supported configuration matrix for the deployed Horizon version."

$vc = Get-HVVirtualCenter
if (-not $vc) { return }

foreach ($v in $vc) {
    [pscustomobject]@{
        Name              = $v.name
        ServerName        = $v.server_name
        Version           = $v.version
        Build             = $v.build
        ApiVersion        = $v.api_version
        InstanceUuid      = $v.instance_uuid
        CertificateStatus = $v.certificate_override
        Status            = $v.status
        ConcurrentOps     = if ($v.limits) { "{0} pwr / {1} prov / {2} maint" -f `
                              $v.limits.max_concurrent_power_operations, `
                              $v.limits.max_concurrent_provisioning_operations, `
                              $v.limits.max_concurrent_maintenance_operations } else { '' }
    }
}

$TableFormat = @{
    Status = { param($v,$row) if ($v -and $v -ne 'OK') { 'bad' } else { '' } }
}
