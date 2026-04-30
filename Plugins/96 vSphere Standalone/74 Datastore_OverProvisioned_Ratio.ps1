# Start of Settings
$WarnRatio = 1.5    # provisioned > 1.5x capacity
$BadRatio  = 2.0
# End of Settings

$Title          = 'Datastore Over-Provisioned Ratio'
$Header         = '[count] datastore(s) over-provisioned beyond ' + $WarnRatio + 'x'
$Comments       = "Sum of all VMDK 'Capacity' (provisioned) divided by datastore Capacity. Thin provisioning lets you exceed 1.0x; ratios > 1.5x risk silent OOS-on-datastore when VMs grow into their thick claims. Track week-over-week growth to spot runaway."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P2'
$Recommendation = 'For each over-provisioned datastore: identify thin VMs growing fastest (3x weekly?), Storage vMotion to a less-loaded datastore, or expand the LUN. Long-term: Storage DRS with anti-affinity rules + storage policy compliance.'

if (-not $Global:VCConnected) { return }

foreach ($ds in (Get-Datastore -ErrorAction SilentlyContinue | Where-Object { $_.Type -in 'VMFS','NFS','NFS41' } | Sort-Object Name)) {
    try {
        $cap = $ds.CapacityGB
        if ($cap -le 0) { continue }
        $vms = @(Get-VM -Datastore $ds -ErrorAction SilentlyContinue)
        $provGB = 0
        foreach ($vm in $vms) {
            foreach ($d in (Get-HardDisk -VM $vm -ErrorAction SilentlyContinue)) {
                if ($d.Filename -and $d.Filename -match [regex]::Escape($ds.Name)) {
                    $provGB += $d.CapacityGB
                }
            }
        }
        $ratio = if ($cap -gt 0) { [math]::Round($provGB/$cap, 2) } else { 0 }
        if ($ratio -ge $WarnRatio) {
            [pscustomobject]@{
                Datastore       = $ds.Name
                CapacityGB      = [math]::Round($cap,1)
                ProvisionedGB   = [math]::Round($provGB,1)
                Ratio           = "$ratio : 1"
                FreeGB          = [math]::Round($ds.FreeSpaceGB,1)
                VMCount         = $vms.Count
            }
        }
    } catch { }
}

$TableFormat = @{
    Ratio = { param($v,$row)
        $r = [decimal]([string]$v -replace ' : 1','')
        if ($r -ge $BadRatio) { 'bad' } elseif ($r -ge $WarnRatio) { 'warn' } else { '' }
    }
}
