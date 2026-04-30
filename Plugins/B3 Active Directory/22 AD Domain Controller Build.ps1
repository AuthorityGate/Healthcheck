# Start of Settings
# End of Settings

$Title          = 'AD Domain Controller OS / Build / Patch Currency'
$Header         = 'Every DC: OS, build, install date, last reboot, time-source chain'
$Comments       = 'Active Directory replication health and security posture depend on DCs being current and consistently patched. Lists every DC with operating system, build number, install date, last boot, hotfix count if reachable, and the W32Time peer chain.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = 'B3 Active Directory'
$Severity       = 'P2'
$Recommendation = "All DCs in a domain SHOULD run the same OS major version (Server 2019/2022/2025). Patch within 30 days of Patch Tuesday. PDC Emulator is the authoritative time source - confirm it points at an external NTP source via 'w32tm /query /configuration'."

if (-not (Test-Path Variable:Global:ADForestFqdn) -or -not $Global:ADForestFqdn) { return }
try { Import-Module ActiveDirectory -ErrorAction Stop } catch { return }

$adArgs = @{ Server = $(if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { $Global:ADForestFqdn }) }
if (Test-Path Variable:Global:ADCredential) { $adArgs.Credential = $Global:ADCredential }

try {
    $forest = Get-ADForest -Identity $Global:ADForestFqdn @adArgs -ErrorAction Stop
    foreach ($d in $forest.Domains) {
        $a = @{ Filter='*'; Server=$d; ErrorAction='SilentlyContinue' }
        if (Test-Path Variable:Global:ADCredential) { $a.Credential = $Global:ADCredential }
        $dcs = @(Get-ADDomainController @a)
        if ($dcs.Count -eq 0) {
            [pscustomobject]@{ Domain=$d; Status='NO DCs RETURNED' }
            continue
        }
        # Capture OS uniformity
        $osList = @($dcs | Select-Object -ExpandProperty OperatingSystem -Unique)
        $uniformOS = $osList.Count -le 1

        foreach ($dc in $dcs) {
            $boot = $null; $patches = $null; $w32time = ''; $cimErr = ''
            try {
                $cim = Get-CimInstance -ComputerName $dc.HostName -ClassName Win32_OperatingSystem -ErrorAction Stop
                $boot = $cim.LastBootUpTime
                # Hotfix count is best-effort
                try { $patches = (Get-CimInstance -ComputerName $dc.HostName -ClassName Win32_QuickFixEngineering -ErrorAction Stop).Count } catch { }
                try {
                    $w32 = Invoke-Command -ComputerName $dc.HostName -ScriptBlock { w32tm /query /source 2>$null } -ErrorAction Stop
                    $w32time = ($w32 | Select-Object -First 1)
                } catch { }
            } catch {
                $cimErr = "CIM err: $($_.Exception.Message.Split([Environment]::NewLine)[0])"
            }
            $uptimeDays = if ($boot) { [int]((Get-Date) - $boot).TotalDays } else { '' }
            $status = if ($cimErr) { "WARN ($cimErr)" }
                      elseif (-not $uniformOS) { 'WARN (mixed OS in domain)' }
                      elseif ([int]"$uptimeDays" -gt 60) { 'WARN (>60 day uptime - patching due)' }
                      else { 'OK' }
            [pscustomobject]@{
                Domain         = $d
                DC             = $dc.HostName
                Site           = $dc.Site
                IsGlobalCatalog= [bool]$dc.IsGlobalCatalog
                IsReadOnly     = [bool]$dc.IsReadOnly
                OperatingSystem= "$($dc.OperatingSystem)"
                OSVersion      = "$($dc.OperatingSystemVersion)"
                LastBoot       = if ($boot) { $boot.ToString('yyyy-MM-dd HH:mm') } else { '(unreachable)' }
                UptimeDays     = $uptimeDays
                HotfixCount    = if ($patches) { $patches } else { '' }
                W32TimeSource  = "$w32time"
                Status         = $status
            }
        }
    }
} catch {
    [pscustomobject]@{ Domain='ERROR'; Status=$_.Exception.Message }
}

$TableFormat = @{
    UptimeDays = { param($v,$row) if ("$v" -match '^\d+$' -and [int]"$v" -gt 60) { 'warn' } else { '' } }
    IsGlobalCatalog = { param($v,$row) if ($v -eq $false) { 'warn' } else { '' } }
    Status     = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -match 'WARN|NO ') { 'warn' } else { '' } }
}
