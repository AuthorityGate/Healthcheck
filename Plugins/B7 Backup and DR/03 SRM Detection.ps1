# Start of Settings
# End of Settings

$Title          = "VMware Site Recovery Manager Detection"
$Header         = "SRM extension presence on connected vCenter(s)"
$Comments       = "Probes the vCenter ExtensionManager for the SRM extension key (com.vmware.vcDr). Surfaces the SRM server FQDN, version, registration date. Does NOT initiate a recovery plan; this is a presence + version audit only."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B7 Backup and DR"
$Severity       = "Info"
$Recommendation = "Customers with SRM should run quarterly recovery-plan tests. SRM versions older than 8.5 lose support; plan upgrade to current. Customers without SRM should consider it OR document their alternative DR runbook."

if (-not $Global:VCConnected) { return }
$servers = @($global:DefaultVIServers | Where-Object { $_ -and $_.IsConnected })
if ($servers.Count -eq 0 -and $Global:VCServer) { $servers = @([pscustomobject]@{ Name = $Global:VCServer }) }

foreach ($srv in $servers) {
    try {
        $em = Get-View -Id (Get-View ServiceInstance -Server $srv -ErrorAction Stop).Content.ExtensionManager -Server $srv -ErrorAction Stop
        $srm = $em.ExtensionList | Where-Object { $_.Key -match 'vcDr' -or $_.Key -match 'SRM' }
        if (-not $srm) {
            [pscustomobject]@{
                vCenter   = $srv.Name
                SRMPresent = $false
                Version   = ''
                Server    = ''
                Note      = 'SRM extension NOT registered on this vCenter. Either SRM is not deployed OR it was unregistered.'
            }
            continue
        }
        foreach ($ext in $srm) {
            [pscustomobject]@{
                vCenter   = $srv.Name
                SRMPresent = $true
                Version   = $ext.Version
                Server    = if ($ext.Server) { ($ext.Server.Url -join ', ') } else { '' }
                Note      = "Description: $($ext.Description.Summary)"
            }
        }
    } catch {
        [pscustomobject]@{ vCenter=$srv.Name; SRMPresent=''; Version=''; Server=''; Note="Probe failed: $($_.Exception.Message)" }
    }
}

$TableFormat = @{ SRMPresent = { param($v,$row) if ($v -eq $true) { 'ok' } elseif ($v -eq $false) { 'warn' } else { '' } } }
