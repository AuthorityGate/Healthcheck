# Start of Settings
# End of Settings

$Title          = "Storage DRS on Datastores Used by Horizon"
$Header         = "[count] datastore cluster(s) with SDRS Automation in 'Fully Automated'"
$Comments       = "VMware KB 2148895 + Horizon docs: Storage DRS in 'Fully Automated' mode is **not supported** for Horizon (instant clone, linked clone, full clone) - SDRS-initiated Storage vMotion conflicts with View Composer and the Horizon dynamic-environment manager. SDRS may be set to 'Manual' (recommendation only)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P1"
$Recommendation = "Datastore cluster -> Edit Settings -> set Storage DRS to 'Manual' or disable. Confirm no Horizon pool is configured to use the datastore cluster as a single target with SDRS Automatic."

if (-not $Global:VCConnected) { return }

Get-DatastoreCluster -ErrorAction SilentlyContinue | Where-Object {
    $_.SdrsAutomationLevel -eq 'FullyAutomated'
} | ForEach-Object {
    $cap = [double]$_.CapacityGB
    $free = [double]$_.FreeSpaceGB
    $pct = if ($cap -gt 0) { [math]::Round((($cap - $free) / $cap) * 100, 1) } else { '' }
    [pscustomobject]@{
        DatastoreCluster = $_.Name
        SdrsAutomation   = $_.SdrsAutomationLevel
        IOLoadBalance    = $_.IOLoadBalanceEnabled
        SpaceUtilization = if ("$pct" -ne '') { "$pct%" } else { '(unknown)' }
        MemberDatastores = @($_ | Get-Datastore -ErrorAction SilentlyContinue).Count
    }
}

$TableFormat = @{
    SdrsAutomation = { param($v,$row) 'bad' }
}
