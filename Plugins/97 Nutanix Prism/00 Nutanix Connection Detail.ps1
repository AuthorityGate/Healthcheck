# Start of Settings
# End of Settings

$Title          = "Nutanix Connection Detail"
$Header         = "Connected Prism target + calling-user role + endpoint reachability"
$Comments       = "First plugin in the Nutanix scope. Echoes the Prism Central / Element FQDN we're authenticated against, the AOS / pc.YYYY.MM version, the calling-user role + permission count, and which v3 endpoints answered on connect. Use this to confirm the service account has the read-only permissions we need before reading the rest of the report."
$Display        = "List"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "Info"
$Recommendation = "If 'Permissions' is empty, the role binding is too narrow - rebind the service account with the AuthorityGate-HealthCheck-ReadOnly role (see docs/Nutanix-ReadOnly-Role.json). If endpoints show 403, that specific permission is missing; add it to the role and re-run."

$s = Get-NTNXRestSession
if (-not $s) {
    [pscustomobject]@{
        Status = '(not connected)'
        Note   = 'Nutanix plugins skip. Provide a Prism Central FQDN in the GUI or pass -NTNXServer.'
    }
    return
}

# Probe a few well-known v3 endpoints so the report shows what the role
# actually grants. Each call records its outcome via Get-NTNXPathProbe.
foreach ($probe in @('/clusters/list','/hosts/list','/vms/list','/storage_containers/list','/alerts/list','/audits/list','/tasks/list')) {
    try { $null = Invoke-NTNXRest -Path $probe -ErrorAction SilentlyContinue } catch { }
}
$probeRows = Get-NTNXPathProbe
$summary = @($probeRows | Group-Object Path | ForEach-Object {
    $hit = $_.Group | Where-Object Status -eq 200 | Select-Object -First 1
    if (-not $hit) { $hit = $_.Group | Select-Object -First 1 }
    "$($_.Name)=$($hit.Status)"
}) -join ', '

[pscustomobject]@{
    'Prism Target'    = $s.Server
    'Port'            = $s.Port
    'Base URL'        = $s.BaseUrl
    'Connected At'    = $s.ConnectedAt
    'Calling User'    = if ($s.CallingUser -and $s.CallingUser.status) { $s.CallingUser.status.name } else { $s.Credential.UserName }
    'Permissions'     = if ($s.Permissions) { ($s.Permissions -join ', ') } else { '(empty - role may be misbound)' }
    'Endpoint Probe'  = $summary
    'Skip-Cert-Check' = $s.SkipCertificateCheck
}
