# Start of Settings
# End of Settings

$Title          = 'UAG Syslog Forwarding'
$Header         = 'Syslog target configured'
$Comments       = 'Without syslog forwarding, UAG events live only in /opt/vmware/gateway/logs and are lost on reboot.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '90 Gateways'
$Severity       = 'P2'
$Recommendation = 'Configure syslog over TCP/TLS to the SIEM. Test by triggering a failed login.'

if (-not (Get-UAGRestSession)) { return }
$s = Get-UAGSyslogSetting
if (-not $s) { return }
[pscustomobject]@{
    SyslogUrl    = $s.syslogUrl
    SyslogType   = $s.syslogType
    SyslogFormat = $s.syslogFormat
}
