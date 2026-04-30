# Start of Settings
# End of Settings

$Title          = 'vSphere TLS Profile'
$Header         = 'Outdated TLS / cipher allowed on hosts'
$Comments       = 'Reference: KB 2147469 / vSphere hardening. TLS 1.0/1.1 must be disabled on all ESXi management.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P1'
$Recommendation = 'esxcli system tls server set --tls-versions=1.2,1.3 (or via host profile).'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $tls = (Get-AdvancedSetting -Entity $_ -Name 'UserVars.ESXiVPsAllowedProtocols' -ErrorAction SilentlyContinue).Value
    if ($tls -and ($tls -match 'tlsv1.0|tlsv1.1')) {
        [pscustomobject]@{ Host=$_.Name; TlsProtocols=$tls }
    }
}
