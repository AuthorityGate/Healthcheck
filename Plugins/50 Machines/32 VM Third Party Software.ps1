# Start of Settings
if (-not $Global:VMSoftwareProbeMax) { $Global:VMSoftwareProbeMax = 25 }
# Categories of software we explicitly look for, beyond the EUC stack
# (which is covered by 31 VM EUC Agent Inventory). Add to / extend per
# customer engagement.
$AntivirusMatches = @('CrowdStrike','SentinelOne','Cylance','McAfee','Symantec','Sophos','TrendMicro',
                     'Defender for Endpoint','Carbon Black','Cortex XDR','MalwareBytes','Webroot','ESET','Bitdefender')
$MonitoringMatches = @('SolarWinds','Datadog','New Relic','LogicMonitor','Nagios','PRTG','Zabbix','SCOM',
                      'Splunk Universal Forwarder','Elastic Agent','Wazuh','Tanium','Qualys','Rapid7','Tenable')
$BrowserMatches = @('Chrome','Firefox','Edge','Brave','Vivaldi','Opera')
$OfficeMatches = @('Microsoft 365','Office 365','Office Standard','Office Professional','Visio','Project','Skype for Business','Teams')
$RemoteAccessMatches = @('TeamViewer','LogMeIn','GoToAssist','Splashtop','AnyDesk','BeyondTrust')
# End of Settings

$Title          = "VM Third-Party Software Inventory (Tier 2)"
$Header         = "[count] VM(s) probed for non-EUC software"
$Comments       = @"
Reads each sampled VM's installed-software registry (HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall + WOW6432Node) and surfaces:
- Antivirus / EDR (CrowdStrike, SentinelOne, McAfee, Defender, etc.)
- Monitoring agents (SolarWinds, Splunk, Datadog, Tanium, etc.)
- Browsers + versions
- Office productivity suite versions
- Remote-access tools (red flag if found in production VDI)

Smaller sample size than the OS+Patch plugin because Win32_Product is intentionally avoided (slow + has side effects); we read the registry uninstall keys directly. Operator can lift `$Global:VMSoftwareProbeMax.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "50 Machines"
$Severity       = "P3"
$Recommendation = "Inconsistent AV / EDR across the VDI fleet = compliance gap. Browser drift across pools = profile portability issues. Remote-access tools (TeamViewer / AnyDesk) on production VDI = security policy concern; remove unless explicitly approved."

if (-not (Get-HVRestSession)) { return }
$cred = $Global:HVImageScanCredential
if (-not $cred) {
    [pscustomobject]@{ Note = 'No Tier-2 credential.' }
    return
}

$pools = @(Get-HVDesktopPool)
$allMachines = @(Get-HVMachine)
$sample = New-Object System.Collections.ArrayList
foreach ($pool in $pools) {
    if (-not $pool.id) { continue }
    $first = $allMachines | Where-Object { $_.desktop_pool_id -eq $pool.id -and $_.dns_name } | Select-Object -First 1
    if ($first) { [void]$sample.Add($first) }
    if ($sample.Count -ge $Global:VMSoftwareProbeMax) { break }
}

if ($sample.Count -eq 0) { return }

$probeBlock = {
    param($AvList,$MonList,$BrwList,$OffList,$RaList)
    $all = @()
    foreach ($p in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        $items = Get-ItemProperty $p -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
        $all += $items
    }
    function MatchOne {
        param($Items,[string[]]$Patterns)
        $hits = @()
        foreach ($pat in $Patterns) {
            foreach ($i in $Items) {
                if ($i.DisplayName -like "*$pat*") {
                    $hits += "$($i.DisplayName) $($i.DisplayVersion)"
                    break
                }
            }
        }
        return ($hits | Select-Object -Unique) -join '; '
    }
    [pscustomobject]@{
        Antivirus    = MatchOne $all $AvList
        Monitoring   = MatchOne $all $MonList
        Browsers     = MatchOne $all $BrwList
        Office       = MatchOne $all $OffList
        RemoteAccess = MatchOne $all $RaList
        TotalCount   = $all.Count
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
        [pscustomobject]@{ VM=$m.dns_name; Pool=$m.desktop_pool_id; Antivirus='(WinRM unreachable)'; Monitoring=''; Browsers=''; Office=''; RemoteAccess=''; TotalCount='' }
        continue
    }
    try {
        $session = New-PSSession -ComputerName $m.dns_name -Credential $cred -ErrorAction Stop
        $r = Invoke-Command -Session $session -ScriptBlock $probeBlock -ArgumentList $AntivirusMatches, $MonitoringMatches, $BrowserMatches, $OfficeMatches, $RemoteAccessMatches -ErrorAction Stop
        Remove-PSSession $session -ErrorAction SilentlyContinue
        [pscustomobject]@{
            VM           = $m.dns_name
            Pool         = $m.desktop_pool_id
            Antivirus    = $r.Antivirus
            Monitoring   = $r.Monitoring
            Browsers     = $r.Browsers
            Office       = $r.Office
            RemoteAccess = $r.RemoteAccess
            TotalCount   = $r.TotalCount
        }
    } catch {
        [pscustomobject]@{ VM=$m.dns_name; Pool=$m.desktop_pool_id; Antivirus='(probe failed)'; Note=$_.Exception.Message.Substring(0,[Math]::Min(100,$_.Exception.Message.Length)) }
    }
}

$TableFormat = @{
    Antivirus = { param($v,$row) if (-not $v -or $v -eq '(WinRM unreachable)' -or $v -eq '(probe failed)') { '' } else { 'ok' } }
    RemoteAccess = { param($v,$row) if ($v -and $v -notmatch 'unreachable|failed') { 'warn' } else { '' } }
}
