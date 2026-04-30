# Start of Settings
# Sample size cap. Probing 5000 VDIs via WinRM costs hours; a 50-VM sample
# across all pools is enough to characterize the fleet. Operator can lift
# via $Global:VMPatchProbeMax.
$DefaultSampleSize = 50
if (-not $Global:VMPatchProbeMax) { $Global:VMPatchProbeMax = $DefaultSampleSize }
# End of Settings

$Title          = "VM OS + Windows Build + Hotfix Inventory (Tier 2)"
$Header         = "[count] Horizon-managed VM(s) probed via WinRM"
$Comments       = @"
Tier-2 (PSRemoting) deep scan: connects to a sample of Horizon-managed VMs and reads:
- Full Windows build (e.g. Windows 11 23H2, build 22631.4317)
- Edition (Pro / Enterprise / LTSC)
- Last-installed hotfix + age
- Pending reboot status
- Patch count (Get-HotFix)
- Total uptime

Sample defaults to $DefaultSampleSize VMs across all pools (set `$Global:VMPatchProbeMax to widen). Requires `$Global:HVImageScanCredential set via the GUI (Set Deep-Scan Creds button) AND WinRM TCP/5985 reachable. VMs without WinRM open emit a row with the failure reason.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "50 Machines"
$Severity       = "Info"
$Recommendation = "VMs > 60 days since last patch = patch-cadence gap. Different Windows builds across machines in the SAME pool = inconsistent base image. Pending reboot = a previously-installed patch is not in effect; reboot via Horizon admin or Windows Update."

if (-not (Get-HVRestSession)) { return }
$cred = $Global:HVImageScanCredential
if (-not $cred) {
    [pscustomobject]@{ Note = 'No Tier-2 credential. Click "Set Deep-Scan Creds..." on the GUI toolbar to enable per-VM probes.' }
    return
}

# Build sample: take one VM from each pool, then fill the rest by population
$pools = @(Get-HVDesktopPool)
$allMachines = @(Get-HVMachine)
if ($allMachines.Count -eq 0) { return }

$sample = New-Object System.Collections.ArrayList
foreach ($pool in $pools) {
    if (-not $pool.id) { continue }
    $first = $allMachines | Where-Object { $_.desktop_pool_id -eq $pool.id -and $_.dns_name } | Select-Object -First 1
    if ($first) { [void]$sample.Add($first) }
    if ($sample.Count -ge $Global:VMPatchProbeMax) { break }
}
# Fill remaining quota with random machines having a dns_name
if ($sample.Count -lt $Global:VMPatchProbeMax) {
    $remaining = $allMachines |
        Where-Object { $_.dns_name -and ($sample.id -notcontains $_.id) } |
        Get-Random -Count ([Math]::Min(($Global:VMPatchProbeMax - $sample.Count), 1000))
    foreach ($m in @($remaining)) { [void]$sample.Add($m) }
}

if ($sample.Count -eq 0) {
    [pscustomobject]@{ Note = 'No machines with a dns_name to probe.' }
    return
}

$probeBlock = {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $build = ''
    try { $build = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion } catch { }
    if (-not $build) { try { $build = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).ReleaseId } catch { } }
    $ubr = ''
    try { $ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).UBR } catch { }
    $hotfix = $null
    try { $hotfix = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1 } catch { }
    $hotfixCount = 0
    try { $hotfixCount = (Get-HotFix -ErrorAction SilentlyContinue | Measure-Object).Count } catch { }
    $pendingReboot = $false
    foreach ($p in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )) { if (Test-Path $p) { $pendingReboot = $true; break } }
    if (-not $pendingReboot) {
        try {
            $sup = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop).PendingFileRenameOperations
            if ($sup) { $pendingReboot = $true }
        } catch { }
    }
    [pscustomobject]@{
        OSCaption     = $os.Caption
        Edition       = $os.OperatingSystemSKU
        Version       = $os.Version
        DisplayVersion = $build
        UBR           = $ubr
        Architecture  = $os.OSArchitecture
        LastBootTime  = $os.LastBootUpTime
        UptimeDays    = if ($os) { [int]((Get-Date) - $os.LastBootUpTime).TotalDays } else { '' }
        HotfixCount   = $hotfixCount
        LastHotfixId  = if ($hotfix) { $hotfix.HotFixID } else { '' }
        LastHotfixDate = if ($hotfix -and $hotfix.InstalledOn) { $hotfix.InstalledOn.ToString('yyyy-MM-dd') } else { '' }
        DaysSincePatch = if ($hotfix -and $hotfix.InstalledOn) { [int]((Get-Date) - $hotfix.InstalledOn).TotalDays } else { '' }
        PendingReboot  = $pendingReboot
        Manufacturer   = $cs.Manufacturer
        Model          = $cs.Model
        TotalRAMGB     = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { '' }
    }
}

foreach ($m in $sample) {
    $tcp = $false
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect($m.dns_name, 5985, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(2500)) { $c.EndConnect($iar); $tcp = $true }
        $c.Close()
    } catch { }
    if (-not $tcp) {
        [pscustomobject]@{ VM=$m.dns_name; Pool=$m.desktop_pool_id; OSCaption='(WinRM/5985 unreachable)'; LastHotfixId=''; DaysSincePatch=''; PendingReboot=''; Note='TCP timeout' }
        continue
    }
    try {
        $session = New-PSSession -ComputerName $m.dns_name -Credential $cred -ErrorAction Stop
        $r = Invoke-Command -Session $session -ScriptBlock $probeBlock -ErrorAction Stop
        Remove-PSSession $session -ErrorAction SilentlyContinue
        [pscustomobject]@{
            VM             = $m.dns_name
            Pool           = $m.desktop_pool_id
            OSCaption      = $r.OSCaption
            DisplayVersion = $r.DisplayVersion
            BuildUBR       = "$($r.Version).$($r.UBR)"
            Architecture   = $r.Architecture
            UptimeDays     = $r.UptimeDays
            HotfixCount    = $r.HotfixCount
            LastHotfixId   = $r.LastHotfixId
            LastHotfixDate = $r.LastHotfixDate
            DaysSincePatch = $r.DaysSincePatch
            PendingReboot  = $r.PendingReboot
            TotalRAMGB     = $r.TotalRAMGB
        }
    } catch {
        [pscustomobject]@{ VM=$m.dns_name; Pool=$m.desktop_pool_id; OSCaption='(probe failed)'; LastHotfixId=''; DaysSincePatch=''; PendingReboot=''; Note=$_.Exception.Message.Substring(0, [Math]::Min(100, $_.Exception.Message.Length)) }
    }
}

$TableFormat = @{
    DaysSincePatch = { param($v,$row) if ([int]"$v" -gt 60) { 'bad' } elseif ([int]"$v" -gt 30) { 'warn' } else { '' } }
    PendingReboot  = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
    UptimeDays     = { param($v,$row) if ([int]"$v" -gt 90) { 'warn' } else { '' } }
}
