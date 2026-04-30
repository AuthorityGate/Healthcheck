#Requires -Version 5.1
<#
    InfraServerScan.psm1

    Companion to GuestImageScan.psm1 - same Tier 1 + Tier 2 pattern, but
    tuned for Windows infrastructure servers (Connection Servers, App
    Volumes Managers, Enrollment Servers, NSX Managers running Windows,
    SQL servers behind Horizon).

    Tier 1: vCenter-side VM hardware + Tools data (always available).
    Tier 2: WinRM in-guest probe (gated on $Global:HVImageScanCredential).

    Returns @{
        Server         = <name>
        Role           = 'ConnectionServer' | 'AppVolumesManager' | 'EnrollmentServer'
        VmHardware     = @{ ... }
        Guest          = @{ ... }            # Tier 2 only
        Tier           = 'Tier1' | 'Tier2'
        Findings       = @( @{ Severity, Rule, Detail, Fix } ... )
    }

    Findings rules cover:
      - OS support level (EOL Windows Server is bad)
      - Hotfix currency
      - Service account (running services + start mode for Horizon/AV/ES service)
      - Cert presence + expiry on the box
      - Defender + EDR presence
      - Event log error counts (last 24h)
      - Per-role specific checks
#>

Set-StrictMode -Version Latest

$Script:InfraRemoteSb = {
    param($Role)
    $r = @{}

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $r.OsCaption     = $os.Caption
        $r.OsVersion     = $os.Version
        $r.OsBuildNumber = $os.BuildNumber
        $r.OsLastBoot    = $os.LastBootUpTime
    } catch { $r.OsError = $_.Exception.Message }

    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $r.HostName       = $cs.Name
        $r.Domain         = $cs.Domain
        $r.PartOfDomain   = [bool]$cs.PartOfDomain
        $r.TotalPhysicalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        $r.NumLogicalCpu  = $cs.NumberOfLogicalProcessors
    } catch { }

    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $r.DisplayVersion = $cv.DisplayVersion
        $r.UBR            = $cv.UBR
        $r.ProductName    = $cv.ProductName
    } catch { }

    try {
        $hf = Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First 5
        $r.RecentHotfixes = @($hf | Select-Object HotFixID, Description, InstalledOn)
        if ($hf -and $hf.Count -gt 0) {
            $r.LastHotfixInstalledOn = $hf[0].InstalledOn
        }
    } catch { }

    # Role-specific service + registry probes
    switch ($Role) {
        'ConnectionServer' {
            try {
                $svc = Get-Service -Name 'wsbroker' -ErrorAction Stop
                $r.HorizonBrokerService = @{ Status=$svc.Status; StartType=$svc.StartType }
            } catch { }
            try {
                $svc = Get-Service -Name 'wsnmsvc' -ErrorAction Stop
                $r.HorizonMsgService = @{ Status=$svc.Status; StartType=$svc.StartType }
            } catch { }
            try {
                $reg = Get-ItemProperty 'HKLM:\SOFTWARE\VMware, Inc.\VMware VDM' -ErrorAction Stop
                $r.HorizonCSVersion = $reg.ProductVersion
                $r.HorizonCSBuild   = $reg.ProductBuildNo
            } catch { }
            try {
                $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Omnissa\VDM' -ErrorAction Stop
                if ($reg.ProductVersion) { $r.HorizonCSVersion = $reg.ProductVersion }
            } catch { }
            # Cert with friendly-name 'vdm'
            try {
                $cert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction Stop |
                        Where-Object { $_.FriendlyName -eq 'vdm' } | Select-Object -First 1
                if ($cert) {
                    $r.CSCertSubject = $cert.Subject
                    $r.CSCertNotAfter = $cert.NotAfter
                    $r.CSCertDaysToExpiry = [int]($cert.NotAfter - (Get-Date)).TotalDays
                }
            } catch { }
        }
        'AppVolumesManager' {
            try {
                $svc = Get-Service -Name 'svservice' -ErrorAction SilentlyContinue
                if (-not $svc) { $svc = Get-Service -Name 'CVManager' -ErrorAction SilentlyContinue }
                if (-not $svc) { $svc = Get-Service -DisplayName '*App Volumes*' -ErrorAction SilentlyContinue | Select-Object -First 1 }
                if ($svc) { $r.AVMService = @{ Name=$svc.Name; Status=$svc.Status; StartType=$svc.StartType } }
            } catch { }
            try {
                $reg = Get-ItemProperty 'HKLM:\SOFTWARE\CloudVolumes\Manager' -ErrorAction Stop
                $r.AVMVersion = $reg.Version
            } catch { }
        }
        'EnrollmentServer' {
            try {
                $svc = Get-Service -DisplayName '*Enrollment*' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($svc) { $r.ESService = @{ Name=$svc.Name; Status=$svc.Status; StartType=$svc.StartType } }
            } catch { }
            try {
                $reg = Get-ItemProperty 'HKLM:\SOFTWARE\VMware, Inc.\VMware VDM\Enrollment Server' -ErrorAction Stop
                $r.ESVersion = $reg.ProductVersion
            } catch { }
            # EA cert (Enrollment Agent)
            try {
                $eaCert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction Stop |
                          Where-Object { $_.EnhancedKeyUsageList -match 'Certificate Request Agent' } |
                          Select-Object -First 1
                if ($eaCert) {
                    $r.EACertSubject = $eaCert.Subject
                    $r.EACertNotAfter = $eaCert.NotAfter
                    $r.EACertDaysToExpiry = [int]($eaCert.NotAfter - (Get-Date)).TotalDays
                }
            } catch { }
        }
    }

    # Common: Defender state
    try {
        $mp = Get-MpPreference -ErrorAction Stop
        $r.DefenderRealtime = -not $mp.DisableRealtimeMonitoring
        $r.DefenderExclusionPath = @($mp.ExclusionPath)
    } catch { }

    # Recent error events (last 24h, top 5)
    try {
        $start = (Get-Date).AddHours(-24)
        $events = Get-WinEvent -FilterHashtable @{ LogName='Application'; Level=1,2; StartTime=$start } -MaxEvents 50 -ErrorAction SilentlyContinue
        $r.RecentErrorCount = if ($events) { $events.Count } else { 0 }
        $r.RecentErrorSamples = @($events | Select-Object -First 5 | ForEach-Object { @{ Provider=$_.ProviderName; Id=$_.Id; Message=($_.Message -split "`n")[0] } })
    } catch { $r.RecentErrorCount = $null }

    # IIS state - relevant for CS web frontend
    try {
        $iis = Get-Service -Name 'W3SVC' -ErrorAction SilentlyContinue
        if ($iis) { $r.IISStatus = $iis.Status }
    } catch { }

    return $r
}

function Get-InfraServerScan {
<#
    .SYNOPSIS
    Run an infrastructure-server scan against a single Windows server.

    .PARAMETER ServerFqdn
    DNS / FQDN of the server to probe.

    .PARAMETER Role
    'ConnectionServer' | 'AppVolumesManager' | 'EnrollmentServer'

    .PARAMETER Credential
    PSCredential for WinRM. Without it, returns Tier 1 (no in-guest data).

    .PARAMETER Vm
    Optional PowerCLI VM object - if the server is a known vCenter VM,
    gives Tier 1 hardware data. If not supplied, Tier 1 is skipped.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ServerFqdn,
        [Parameter(Mandatory)][ValidateSet('ConnectionServer','AppVolumesManager','EnrollmentServer')][string]$Role,
        [System.Management.Automation.PSCredential]$Credential,
        $Vm
    )

    $out = @{
        Server     = $ServerFqdn
        Role       = $Role
        VmHardware = @{}
        Guest      = @{}
        Tier       = 'Tier1'
        Findings   = @()
    }

    if ($Vm) {
        $cfg = $Vm.ExtensionData.Config
        $out.VmHardware = @{
            VmName       = $Vm.Name
            vCpu         = $Vm.NumCpu
            RamGB        = [math]::Round($Vm.MemoryGB, 0)
            HardwareVer  = $Vm.HardwareVersion
            Firmware     = $cfg.Firmware
            GuestOS      = if ($Vm.Guest.OSFullName) { $Vm.Guest.OSFullName } else { $cfg.GuestFullName }
            IPAddress    = if ($Vm.Guest.IPAddress) { @($Vm.Guest.IPAddress)[0] } else { '' }
            ToolsRunning = ($Vm.Guest.State -eq 'Running')
        }
    }

    # Tier 2 in-guest probe. Path A: WinRM PSSession. Path B fallback:
    # Invoke-VMScript via VMware Tools (works when guest NIC is disconnected).
    # On a non-domain-joined runner, Kerberos auth fails because there's no
    # SPN in the runner's domain context. We fall through:
    #   1. Default WinRM (Kerberos when domain-joined)
    #   2. Negotiate auth with TrustedHosts (auto-add the target if missing)
    #   3. WinRM HTTPS on 5986 (works without TrustedHosts when CS has cert)
    if ($Credential) {
        $winrmOK = $false
        $tcp5985 = $false
        $tcp5986 = $false
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $async = $tcp.BeginConnect($ServerFqdn, 5985, $null, $null)
            $tcp5985 = $async.AsyncWaitHandle.WaitOne(2000, $false) -and $tcp.Connected
            $tcp.Close()
        } catch { }
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $async = $tcp.BeginConnect($ServerFqdn, 5986, $null, $null)
            $tcp5986 = $async.AsyncWaitHandle.WaitOne(2000, $false) -and $tcp.Connected
            $tcp.Close()
        } catch { }

        $authAttempts = New-Object System.Collections.ArrayList

        if ($tcp5985 -or $tcp5986) {
            # Attempt 1: default (Kerberos / Negotiate). Works on domain-joined runner.
            if ($tcp5985 -and -not $winrmOK) {
                try {
                    $session = New-PSSession -ComputerName $ServerFqdn -Credential $Credential -ErrorAction Stop
                    $remote = Invoke-Command -Session $session -ScriptBlock $Script:InfraRemoteSb -ArgumentList $Role
                    Remove-PSSession $session -ErrorAction SilentlyContinue
                    $out.Guest = $remote; $out.Tier = 'Tier2'; $winrmOK = $true
                    [void]$authAttempts.Add('default-5985:OK')
                } catch {
                    [void]$authAttempts.Add("default-5985:$($_.Exception.Message)")
                }
            }

            # Attempt 2: Negotiate auth with TrustedHosts. Required when the
            # runner is NOT domain-joined; Kerberos has no SPN to resolve.
            if ($tcp5985 -and -not $winrmOK) {
                try {
                    # Auto-add the target to TrustedHosts (idempotent, no-op when present).
                    # Requires elevation. If denied, falls through to next attempt.
                    $thOk = $false
                    try {
                        $thKey = 'WSMan:\localhost\Client\TrustedHosts'
                        $current = (Get-Item -Path $thKey -ErrorAction Stop).Value
                        if ($current -ne '*' -and ($current -split ',' | ForEach-Object { $_.Trim() }) -notcontains $ServerFqdn) {
                            $newList = if ($current) { "$current,$ServerFqdn" } else { $ServerFqdn }
                            Set-Item -Path $thKey -Value $newList -Force -ErrorAction Stop
                        }
                        $thOk = $true
                    } catch {
                        [void]$authAttempts.Add("trustedhosts-add-failed:$($_.Exception.Message) (run elevated to fix, OR manually: 'Set-Item WSMan:\\localhost\\Client\\TrustedHosts $ServerFqdn -Force')")
                    }
                    if ($thOk) {
                        $session = New-PSSession -ComputerName $ServerFqdn -Credential $Credential -Authentication Negotiate -ErrorAction Stop
                        $remote = Invoke-Command -Session $session -ScriptBlock $Script:InfraRemoteSb -ArgumentList $Role
                        Remove-PSSession $session -ErrorAction SilentlyContinue
                        $out.Guest = $remote; $out.Tier = 'Tier2'; $winrmOK = $true
                        [void]$authAttempts.Add('negotiate-trustedhosts-5985:OK')
                    }
                } catch {
                    [void]$authAttempts.Add("negotiate-5985:$($_.Exception.Message)")
                }
            }

            # Attempt 3: WinRM HTTPS on 5986. Works without TrustedHosts when
            # the CS has a valid SSL listener cert.
            if ($tcp5986 -and -not $winrmOK) {
                try {
                    $sopt = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
                    $session = New-PSSession -ComputerName $ServerFqdn -Credential $Credential -UseSSL -Port 5986 -SessionOption $sopt -ErrorAction Stop
                    $remote = Invoke-Command -Session $session -ScriptBlock $Script:InfraRemoteSb -ArgumentList $Role
                    Remove-PSSession $session -ErrorAction SilentlyContinue
                    $out.Guest = $remote; $out.Tier = 'Tier2'; $winrmOK = $true
                    [void]$authAttempts.Add('https-5986:OK')
                } catch {
                    [void]$authAttempts.Add("https-5986:$($_.Exception.Message)")
                }
            }

            if (-not $winrmOK) {
                $out.Guest.WinRmError = "All WinRM attempts failed. " + ($authAttempts -join ' | ')
            }
        } else {
            $out.Guest.WinRmError = 'Neither WinRM 5985 nor 5986 reachable; check firewall + WinRM listener (winrm quickconfig). Trying VMware Tools fallback.'
        }
        # Fallback: Invoke-VMScript when we have a VM object + Tools running
        if (-not $winrmOK -and $Vm -and $out.VmHardware.ToolsRunning) {
            try {
                $sbText = $Script:InfraRemoteSb.ToString()
                $wrappedScript = @"
`$ProgressPreference = 'SilentlyContinue'
`$result = & { $sbText } -Role '$Role' 2>`$null
'<<<JSON_BEGIN>>>'
`$result | ConvertTo-Json -Depth 6 -Compress
'<<<JSON_END>>>'
"@
                $vmScript = Invoke-VMScript -VM $Vm -ScriptText $wrappedScript -GuestCredential $Credential -ScriptType PowerShell -ErrorAction Stop
                $stdout = $vmScript.ScriptOutput
                if ($stdout -match '(?s)<<<JSON_BEGIN>>>\s*(.+?)\s*<<<JSON_END>>>') {
                    $jsonText = $Matches[1].Trim()
                    $remote = $jsonText | ConvertFrom-Json -ErrorAction Stop
                    $remoteHt = @{}
                    foreach ($p in $remote.PSObject.Properties) { $remoteHt[$p.Name] = $p.Value }
                    $out.Guest = $remoteHt
                    $out.Tier  = 'Tier2-VMTools'
                } else {
                    $out.Guest.VMToolsError = "Invoke-VMScript returned no parseable output."
                }
            } catch {
                $out.Guest.VMToolsError = "Invoke-VMScript failed: $($_.Exception.Message)"
            }
        }
    } else {
        $out.Guest.WinRmError = 'No PSCredential supplied; Tier 2 skipped.'
    }

    # ---------- Rule evaluation ----------
    function _add { param($sev, $rule, $detail, $fix)
        $out.Findings += [pscustomobject]@{
            Server   = $ServerFqdn
            Role     = $Role
            Severity = $sev
            Rule     = $rule
            Detail   = $detail
            Fix      = $fix
        }
    }

    # Tier 1 rule: VM right-sizing per role. VmHardware is empty when no
    # vCenter VM was supplied (AD-only or non-vCenter runs); guard the
    # RamGB lookup so it doesn't error 'RamGB cannot be found on this object'.
    $vmRam = if ($out.VmHardware -is [hashtable] -and $out.VmHardware.ContainsKey('RamGB')) { $out.VmHardware['RamGB'] } else { $null }
    if ($vmRam) {
        $minRam = switch ($Role) {
            'ConnectionServer' { 12 }   # Omnissa min 10 GB; rec 16 GB
            'AppVolumesManager' { 8 }
            'EnrollmentServer' { 4 }
        }
        if ($vmRam -lt $minRam) {
            _add 'P2' "$Role undersized RAM" "Has $vmRam GB; minimum $minRam GB recommended for $Role." "Edit VM Settings -> increase RAM to $minRam+ GB and reboot."
        }
    }

    # Tier 2 rules - covers both WinRM and VMware Tools fallback paths.
    if ($out.Tier -in 'Tier2','Tier2-VMTools' -and $out.Guest) {
        $g = $out.Guest

        # OS support level
        if ($g.OsCaption) {
            $isEol = $g.OsCaption -match 'Server 2008|Server 2012(?!\sR2)|Server 2003|Server 2000'
            $isSoonEol = $g.OsCaption -match 'Server 2012 R2|Server 2016'
            if ($isEol) {
                _add 'P1' "$Role on EOL Windows Server" "$($g.OsCaption) is past end of support. Microsoft does not provide security updates." "Plan migration to Windows Server 2022 / 2025."
            } elseif ($isSoonEol) {
                _add 'P3' "$Role on Windows Server approaching EOL" "$($g.OsCaption) - mainstream support expired or expiring." "Plan migration to current Windows Server."
            }
        }

        # Patch lag
        if ($g.LastHotfixInstalledOn) {
            $age = ((Get-Date) - [datetime]$g.LastHotfixInstalledOn).TotalDays
            if ($age -gt 60) {
                _add 'P2' "$Role patch lag" "Last hotfix installed $([int]$age) days ago." "Run Windows Update on the server during a maintenance window."
            }
        }

        # Defender state
        if ($null -ne $g.DefenderRealtime -and $g.DefenderRealtime -eq $false) {
            _add 'P3' "$Role Defender real-time scan disabled" 'Defender real-time monitoring is OFF. Server-level AV/EDR should be enabled (or Defender replaced with another EDR).' 'Verify alternative EDR is present + healthy. Otherwise enable Defender real-time.'
        }

        # Recent error events
        if ($null -ne $g.RecentErrorCount -and $g.RecentErrorCount -gt 50) {
            _add 'P3' "$Role event log: error volume" "$($g.RecentErrorCount) Application-level errors in last 24h." 'Review Event Viewer Application log; investigate top error sources.'
        }

        # Role-specific
        switch ($Role) {
            'ConnectionServer' {
                if ($g.HorizonBrokerService -and $g.HorizonBrokerService.Status -ne 'Running') {
                    _add 'P1' 'Horizon Connection Broker service not Running' "wsbroker service status = $($g.HorizonBrokerService.Status)." 'Start the VMware Horizon Connection Server service. Investigate why it stopped.'
                }
                if ($g.CSCertDaysToExpiry -ne $null -and $g.CSCertDaysToExpiry -lt 60) {
                    _add 'P1' 'CS SSL certificate expiring soon' "Cert with friendly name vdm expires in $($g.CSCertDaysToExpiry) days." 'Renew cert via enterprise CA, install in Personal store, set friendly name = vdm, restart Connection Server service.'
                }
                if (-not $g.HorizonCSVersion) {
                    _add 'P3' 'CS version registry not found' 'Could not read Horizon Connection Server version from registry. May indicate broken install or version drift.' 'Verify Horizon Connection Server is properly installed.'
                }
            }
            'AppVolumesManager' {
                if (-not $g.AVMService) {
                    _add 'P1' 'App Volumes Manager service not detected' 'Could not find App Volumes Manager Windows service.' 'Verify AVM is installed; check Services console for the AVM service.'
                } elseif ($g.AVMService.Status -ne 'Running') {
                    _add 'P1' 'App Volumes Manager service not Running' "Service $($g.AVMService.Name) status = $($g.AVMService.Status)." 'Start the App Volumes Manager service. Check Application event log for startup errors.'
                }
                if (-not $g.AVMVersion) {
                    _add 'P3' 'AVM version registry not found' 'Could not read AVM version. May indicate broken install.' 'Verify AVM installation health.'
                }
            }
            'EnrollmentServer' {
                if (-not $g.ESService) {
                    _add 'P1' 'Enrollment Server service not detected' 'Could not find Enrollment Server Windows service.' 'Verify ES is installed; check Services console.'
                } elseif ($g.ESService.Status -ne 'Running') {
                    _add 'P1' 'Enrollment Server service not Running' "Service $($g.ESService.Name) status = $($g.ESService.Status)." 'Start the ES service. Check Application event log for startup errors.'
                }
                if ($g.EACertDaysToExpiry -ne $null -and $g.EACertDaysToExpiry -lt 90) {
                    _add 'P1' 'Enrollment Agent certificate expiring soon' "EA cert expires in $($g.EACertDaysToExpiry) days. When it expires, True SSO breaks for everyone." 'Renew the Enrollment Agent cert per CA admin procedure. Re-register the cert with the ES service.'
                }
                if (-not $g.EACertSubject) {
                    _add 'P2' 'Enrollment Agent cert not found' 'No certificate with Certificate Request Agent EKU in LocalMachine\\My store.' 'Enroll the EA cert per the Horizon True SSO setup procedure.'
                }
            }
        }
    }

    [pscustomobject]$out
}

Export-ModuleMember -Function Get-InfraServerScan
