# Start of Settings
# End of Settings

$Title          = "ESXi Syslog Forwarding Configured"
$Header         = "[count] host(s) without a remote syslog target"
$Comments       = "VMware KB 2003322 / vSphere Hardening Guide: ESXi must forward logs to a syslog server. Without it, hostd/vmkernel logs are lost on host reboot or VMFS purge. Required for SIEM (Splunk/QRadar/etc.) and audit compliance (PCI/HIPAA)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "Get-AdvancedSetting -Entity (host) -Name Syslog.global.logHost | Set-AdvancedSetting -Value 'tcp://syslog.corp.local:514'. Apply via host profile to all hosts."

if (-not $Global:VCConnected) { return }

Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h    = $_
    $log  = (Get-AdvancedSetting -Entity $h -Name 'Syslog.global.logHost' -ErrorAction SilentlyContinue).Value
    $unique = (Get-AdvancedSetting -Entity $h -Name 'Syslog.global.logDirUnique' -ErrorAction SilentlyContinue).Value
    if (-not $log) {
        [pscustomobject]@{
            Host        = $h.Name
            SyslogHost  = '(none)'
            UniqueDir   = $unique
        }
    }
}

$TableFormat = @{ SyslogHost = { param($v,$row) if ($v -eq '(none)') { 'bad' } else { '' } } }
