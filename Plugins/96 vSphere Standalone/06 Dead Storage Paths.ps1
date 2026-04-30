# Start of Settings
# End of Settings

$Title          = "Dead or Disabled Storage Paths"
$Header         = "[count] storage path(s) in 'Dead' or 'Disabled' state"
$Comments       = "VMware KB 1009039 / 2004684: a 'Dead' path indicates lost connectivity to a HBA / SAN switch port / target. Even with MPIO masking the failure from VMs, a dead path masks subsequent hardware failures. 'Disabled' is administrative."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P1"
$Recommendation = "Investigate cabling, GBIC, fabric zoning, and array port logs. Once resolved, run 'esxcli storage core path list' and 'esxcli storage core adapter rescan -A vmhba<N>'."

if (-not $Global:VCConnected) { return }

Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    Get-ScsiLun -VmHost $h -ErrorAction SilentlyContinue | ForEach-Object {
        $lun = $_
        Get-ScsiLunPath -ScsiLun $lun -ErrorAction SilentlyContinue | Where-Object {
            $_.State -in 'Dead','Disabled'
        } | ForEach-Object {
            [pscustomobject]@{
                Host = $h.Name
                LUN  = $lun.CanonicalName
                Path = $_.Name
                State = $_.State
                Adapter = $_.SanID
            }
        }
    }
}

$TableFormat = @{ State = { param($v,$row) if ($v -eq 'Dead') { 'bad' } else { 'warn' } } }
