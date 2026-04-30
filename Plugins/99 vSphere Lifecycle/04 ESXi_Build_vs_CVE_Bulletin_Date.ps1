# Start of Settings
# End of Settings

$Title          = 'ESXi Build vs CVE Bulletin Date'
$Header         = 'Hosts not refreshed in 90+ days'
$Comments       = 'Hosts > 90 days un-patched accumulate VMSA CVE exposure.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P2'
$Recommendation = 'Run vLCM remediation. Reference: VMSA bulletin index.'

if (-not $Global:VCConnected) { return }
Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $boot = $_.ExtensionData.Summary.Runtime.BootTime
    if ($boot) {
        $age = ([DateTime]::Now - $boot).TotalDays
        if ($age -gt 180) {
            [pscustomobject]@{ Host=$_.Name; BootTime=$boot; UptimeDays=[int]$age }
        }
    }
}
