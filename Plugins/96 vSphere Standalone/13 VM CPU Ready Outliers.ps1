# Start of Settings
# CPU Ready % above this threshold (averaged over the last hour) is reported.
# 5% per vCPU is the conventional warning line. 10% per vCPU is the action line.
$ReadyPctThreshold = 5
$LookbackMinutes   = 60
# End of Settings

$Title          = "VM CPU Ready Outliers"
$Header         = "[count] VM(s) with > $ReadyPctThreshold% CPU ready (avg over $LookbackMinutes min)"
$Comments       = "VMware KB 2002181 / 1017926: 'CPU ready' is the time the VM was ready to run but waiting for a physical CPU. Sustained > 5% per vCPU on a VM means the host is over-committed. > 10% causes user-visible UI lag in VDI."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "Reduce host CPU over-commit ratio (right-size the offending VMs first), or vMotion the VMs to a less-loaded cluster."

if (-not $Global:VCConnected) { return }

$start = (Get-Date).AddMinutes(-$LookbackMinutes)
Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.PowerState -eq 'PoweredOn' } | ForEach-Object {
    $vm = $_
    try {
        $stat = Get-Stat -Entity $vm -Stat 'cpu.ready.summation' -Start $start -ErrorAction SilentlyContinue
        if (-not $stat) { return }
        # cpu.ready.summation reports ms in the 20s sample - convert to %.
        $avgReadyMs = ($stat | Measure-Object Value -Average).Average
        $pct = [math]::Round((($avgReadyMs / 1000) / 20) * 100, 2)
        if ($pct -gt $ReadyPctThreshold) {
            [pscustomobject]@{
                VM        = $vm.Name
                vCPU      = $vm.NumCpu
                ReadyPct  = $pct
                Cluster   = $vm.VMHost.Parent.Name
            }
        }
    } catch { }
} | Sort-Object ReadyPct -Descending

$TableFormat = @{ ReadyPct = { param($v,$row) if ([double]$v -gt 10) { 'bad' } else { 'warn' } } }
