# Start of Settings
# End of Settings

$Title          = 'DRS Affinity / Anti-Affinity Rules'
$Header         = "[count] DRS rule(s) configured across clusters"
$Comments       = "Affinity rules pin VMs together; anti-affinity separates them. For HA: vCenter HA pair, AVM cluster, CS replicas all need anti-affinity. Without rules, DRS may co-locate them = single host loss = mass impact."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Identify HA pairs/triplets in deployment (CS, AVM, vCenter HA, NSX Manager). Create anti-affinity rules. Verify rule status = compliant."

if (-not $Global:VCConnected) { return }

foreach ($cl in (Get-Cluster -ErrorAction SilentlyContinue)) {
    $rules = Get-DrsRule -Cluster $cl -ErrorAction SilentlyContinue
    if (-not $rules -or @($rules).Count -eq 0) {
        [pscustomobject]@{
            Cluster = $cl.Name
            RuleName = '(none)'
            Type = ''
            VMs = ''
            Enabled = ''
            Compliant = ''
            Note = 'No DRS rules - HA pairs may co-locate'
        }
        continue
    }
    foreach ($r in $rules) {
        $vms = if ($r.VMIds) { ($r.VMIds | ForEach-Object { (Get-View $_ -Property Name).Name }) -join ', ' } else { '' }
        [pscustomobject]@{
            Cluster   = $cl.Name
            RuleName  = $r.Name
            Type      = $r.Type
            VMs       = $vms
            Enabled   = $r.Enabled
            Compliant = if ($r.PSObject.Properties.Name -contains 'Compliant') { $r.Compliant } else { '' }
            Note      = ''
        }
    }
}
