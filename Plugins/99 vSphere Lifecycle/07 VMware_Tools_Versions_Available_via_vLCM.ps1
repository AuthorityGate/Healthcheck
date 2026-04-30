# Start of Settings
# End of Settings

$Title          = 'VMware Tools Versions Available via vLCM'
$Header         = 'Available Tools versions vs deployed'
$Comments       = 'vLCM includes Tools updates. Track gap between available and deployed.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P3'
$Recommendation = "Patch via 'Upgrade VMware Tools' on a maintenance schedule."

if (-not $Global:VCConnected) { return }
$dist = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.PowerState -eq 'PoweredOn' } |
    Select-Object @{n='ToolsVersion';e={$_.ExtensionData.Guest.ToolsVersion}} |
    Group-Object ToolsVersion | Sort-Object Count -Descending
$dist | ForEach-Object { [pscustomobject]@{ ToolsVersion=$_.Name; Count=$_.Count } }
