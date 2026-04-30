# Start of Settings
# End of Settings

$Title          = "vCenter Inventory Counts"
$Header         = "Datacenter / Cluster / Host / VM / Datastore / Network counts"
$Comments       = "Topline inventory for capacity-planning and licensing snapshots. One row per datacenter."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "Info"
$Recommendation = "Track these counts month-over-month. >10% growth in VMs without matching license / capacity expansion = silent oversubscription brewing."

if (-not $Global:VCConnected) { return }

# Each Get-* call is wrapped in its own try because PowerCLI 13.x changed
# the parameter set on some cmdlets (Get-VirtualPortGroup, Get-ResourcePool
# no longer accept -Location in some builds), and mixed PowerCLI versions
# in the customer environment otherwise crashed the entire plugin with
# 'A parameter cannot be found that matches parameter name Location.'
function Get-CountFor { param($scriptblock) try { @(& $scriptblock).Count } catch { '(err)' } }

$dcs = @(Get-Datacenter -ErrorAction SilentlyContinue)
if ($dcs.Count -eq 0) {
    [pscustomobject]@{ Note='Get-Datacenter returned no rows.' }
    return
}
foreach ($dc in $dcs) {
    [pscustomobject]@{
        Datacenter    = $dc.Name
        Clusters      = Get-CountFor { Get-Cluster   -Location $dc -ErrorAction SilentlyContinue }
        Hosts         = Get-CountFor { Get-VMHost    -Location $dc -ErrorAction SilentlyContinue }
        VMs           = Get-CountFor { Get-VM        -Location $dc -ErrorAction SilentlyContinue }
        VMsPoweredOn  = Get-CountFor { Get-VM        -Location $dc -ErrorAction SilentlyContinue | Where-Object { $_.PowerState -eq 'PoweredOn' } }
        Datastores    = Get-CountFor { Get-Datastore -Location $dc -ErrorAction SilentlyContinue }
        Networks      = Get-CountFor { Get-VirtualPortGroup -ErrorAction SilentlyContinue }
        ResourcePools = Get-CountFor { Get-ResourcePool -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'Resources' } }
        Folders       = Get-CountFor { Get-Folder    -Location $dc -Type VM -ErrorAction SilentlyContinue }
    }
}
