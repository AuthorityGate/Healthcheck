# Start of Settings
# End of Settings

$Title          = 'Storage DRS Automation Level'
$Header         = '[count] datastore cluster(s) reviewed; non-default rows surfaced'
$Comments       = 'Storage DRS automates Storage vMotion based on space + I/O latency. Default = Manual (recommendations only). FullyAutomated requires confidence in array-side I/O metrics. Note: Storage DRS is INCOMPATIBLE with Horizon parent VMs (KB 2148895) - the dedicated 02 SDRS plugin in 97 catches that.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P3'
$Recommendation = 'Datastore Cluster -> Configure -> Services -> Storage DRS -> Edit. Confirm I/O metric integrations + array compatibility before enabling FullyAutomated.'

if (-not $Global:VCConnected) { return }

foreach ($dsc in (Get-DatastoreCluster -ErrorAction SilentlyContinue | Sort-Object Name)) {
    [pscustomobject]@{
        DatastoreCluster = $dsc.Name
        SDRSEnabled      = $dsc.SdrsAutomationLevel -ne 'Disabled'
        AutomationLevel  = $dsc.SdrsAutomationLevel
        IOLoadBalanceEnabled = $dsc.IOLoadBalanceEnabled
        SpaceUtilizationThreshold = $dsc.SpaceUtilizationThresholdPercent
    }
}

$TableFormat = @{
    AutomationLevel = { param($v,$row) if ($v -eq 'FullyAutomated') { 'warn' } else { '' } }
}
