#Requires -Version 5.1
<#
    GuestImageScan.psm1

    Introspection of Horizon gold / parent / packaging VMs. The
    plugin layer discovers the SET of machines to scan (parents from the
    Horizon REST API, RDSH masters from the Farms API, App Volumes
    packaging machines from the AV REST API). This module does the actual
    "look inside the guest" work for each named machine.

    Two information tiers per VM:
      Tier 1 (always available - no in-guest creds needed):
        - VM hardware (vCPU, RAM, hardware version, firmware, BIOS state)
        - VMware Tools data (guest hostname, IP, full OS name, Tools version)
        - Attached devices, snapshots, encryption flags

      Tier 2 (requires WinRM creds; gated on -Credential param):
        - OS build + UBR / latest patch
        - Installed software (Win32_Product / Uninstall registry walk)
        - Services + StartMode mismatches vs baseline
        - Scheduled tasks (Microsoft-consumer-experience tasks)
        - Defender / AV exclusion configuration
        - Drivers (unsigned / orphan PNP)
        - Registry highlights: VDI optimization keys, hot-add settings
        - Horizon Agent / DEM Agent / App Volumes Agent presence + version

    Tier 1 always runs. Tier 2 runs only when a PSCredential is supplied
    AND WinRM TCP/5985 (or 5986) is reachable to the guest IP.

    Best-practice rules are emitted as Findings:
        @{ Severity='P1|P2|P3'; Rule='...'; Detail='...'; Fix='...' }

    Each plugin wraps Get-GuestImageScan with a per-row projection that
    surfaces Machine + Rule columns to keep the report consistent with
    other host-specific plugins.
#>

Set-StrictMode -Version Latest

# --------------------------------------------------------------------------
# Scriptblock that runs INSIDE the target guest. Returns a hashtable.
# Kept side-effect-free; reads only.
# --------------------------------------------------------------------------
$Script:RemoteSb = {
    $r = @{}

    # OS
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $r.OsCaption       = $os.Caption
        $r.OsVersion       = $os.Version
        $r.OsBuildNumber   = $os.BuildNumber
        $r.OsLastBoot      = $os.LastBootUpTime
        $r.OsInstallDate   = $os.InstallDate
        $r.OsArchitecture  = $os.OSArchitecture
        $r.OsLanguage      = $os.OSLanguage
    } catch { $r.OsError = $_.Exception.Message }

    # UBR (Update Build Revision) - "the small number after the build" -
    # tells you how patched the guest is.
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $r.DisplayVersion  = $cv.DisplayVersion       # e.g., 24H2
        $r.UBR             = $cv.UBR
        $r.ProductName     = $cv.ProductName
        $r.EditionID       = $cv.EditionID
        $r.ReleaseId       = $cv.ReleaseId
    } catch { }

    # Last hotfix
    try {
        $hf = Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First 1
        if ($hf) {
            $r.LastHotfixId      = $hf.HotFixID
            $r.LastHotfixInstalledOn = $hf.InstalledOn
        }
    } catch { }

    # Domain join state
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $r.PartOfDomain = [bool]$cs.PartOfDomain
        $r.Domain       = $cs.Domain
        $r.Workgroup    = $cs.Workgroup
        $r.PCSystemType = $cs.PCSystemType
        $r.HostName     = $cs.Name
    } catch { }

    # Installed software via uninstall registry (the reliable way).
    # Win32_Product is unreliable + side-effect-y. We walk the uninstall keys.
    $installed = @()
    foreach ($p in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        try {
            $installed += Get-ItemProperty $p -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } |
                Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
        } catch { }
    }
    $r.InstalledSoftware = $installed

    # Services
    try {
        $r.Services = Get-Service -ErrorAction Stop | Select-Object Name, DisplayName, Status, StartType
    } catch { $r.Services = @() }

    # Scheduled tasks - we only care about a few well-known consumer-experience
    # tasks that indicate the image was not OSOT-optimized.
    $taskNames = @(
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
        '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask'
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
        '\Microsoft\Windows\Defrag\ScheduledDefrag'
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
        '\Microsoft\Windows\Maintenance\WinSAT'
        '\Microsoft\Windows\WindowsBackup\ConfigNotification'
        '\Microsoft\Windows\WindowsUpdate\Scheduled Start'
    )
    $tasks = @()
    foreach ($t in $taskNames) {
        try {
            $st = Get-ScheduledTask -TaskPath ($t -replace '\\[^\\]+$','\') -TaskName ($t -split '\\')[-1] -ErrorAction SilentlyContinue
            if ($st) { $tasks += [pscustomobject]@{ Path=$t; State=$st.State } }
        } catch { }
    }
    $r.ScheduledTasks = $tasks

    # Defender state + exclusions
    try {
        $mp = Get-MpPreference -ErrorAction Stop
        $r.DefenderExclusionPath      = @($mp.ExclusionPath)
        $r.DefenderExclusionProcess   = @($mp.ExclusionProcess)
        $r.DefenderExclusionExtension = @($mp.ExclusionExtension)
        $r.DefenderRealtime           = -not $mp.DisableRealtimeMonitoring
    } catch { }

    # FSLogix presence + config (registry)
    try {
        $fsl = Get-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction Stop
        $r.FSLogixEnabled       = [bool]$fsl.Enabled
        $r.FSLogixVHDLocations  = @($fsl.VHDLocations)
    } catch { }

    # Horizon Agent
    try {
        $ha = Get-ItemProperty 'HKLM:\SOFTWARE\VMware, Inc.\VMware VDM\Agent' -ErrorAction Stop
        $r.HorizonAgentVersion = $ha.ProductVersion
        $r.HorizonAgentBuild   = $ha.ProductBuildNo
    } catch { }
    # New Omnissa registry path
    try {
        $oa = Get-ItemProperty 'HKLM:\SOFTWARE\Omnissa\VDM\Agent' -ErrorAction Stop
        if ($oa.ProductVersion) { $r.HorizonAgentVersion = $oa.ProductVersion }
    } catch { }

    # DEM (Dynamic Environment Manager) Agent
    try {
        $dem = Get-ItemProperty 'HKLM:\SOFTWARE\VMware, Inc.\Dynamic Environment Manager' -ErrorAction Stop
        $r.DEMVersion = $dem.Version
    } catch { }

    # App Volumes Agent
    try {
        $av = Get-ItemProperty 'HKLM:\SOFTWARE\CloudVolumes\Agent' -ErrorAction Stop
        $r.AppVolumesAgentVersion = $av.Version
        $r.AppVolumesAgentMode    = $av.AgentMode   # ProvisioningMode = capture VM, RuntimeMode = end-user VM
    } catch { }

    # VMware Tools - prefer registry ProductVersion, fall back to vmtoolsd.exe
    # file metadata. Tools 12.x often only writes InstallPath at the root key,
    # with ProductVersion absent, so the file is the authoritative source.
    try {
        $tools = Get-ItemProperty 'HKLM:\SOFTWARE\VMware, Inc.\VMware Tools' -ErrorAction Stop
        if ($tools.ProductVersion) {
            $r.VMwareToolsVersion = $tools.ProductVersion
        } elseif ($tools.InstallPath) {
            $exe = Join-Path $tools.InstallPath 'vmtoolsd.exe'
            if (Test-Path $exe) {
                $r.VMwareToolsVersion = (Get-Item $exe).VersionInfo.ProductVersion
            }
        }
    } catch { }

    # BitLocker on system drive
    try {
        $bl = Get-CimInstance -Namespace 'Root\CIMV2\Security\MicrosoftVolumeEncryption' `
                              -ClassName Win32_EncryptableVolume `
                              -ErrorAction Stop |
              Where-Object { $_.DriveLetter -eq 'C:' }
        if ($bl) {
            $r.BitLockerProtectionStatus = $bl.ProtectionStatus    # 1 = on, 0 = off
            $r.BitLockerConversionStatus = $bl.ConversionStatus
        }
    } catch { }

    # IPv6 enabled?
    try {
        $r.IPv6Enabled = -not (Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction Stop |
            Where-Object { $_.Enabled -eq $false } | Measure-Object).Count
    } catch { }

    # Sysprep generalize residue check (SkipRearm + ImageState)
    try {
        $sp = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform' -ErrorAction SilentlyContinue
        if ($sp) { $r.SkipRearm = $sp.SkipRearm }
    } catch { }
    try {
        $img = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' -ErrorAction SilentlyContinue
        if ($img) { $r.ImageState = $img.ImageState }
    } catch { }

    # RDP listener state (master images often leave RDP enabled)
    try {
        $rdp = Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -ErrorAction Stop
        $r.RdpDenyTSConnections = [bool]$rdp.fDenyTSConnections   # true = RDP disabled (good for masters)
    } catch { }

    # ====================================================================
    # Comprehensive expansion: capture everything a consultant's "Server
    # Documentation" tool would. Every block is independently try/catch'd
    # so a single failure does not abort the rest of the probe.
    # ====================================================================

    # System / chassis (BIOS, manufacturer, model, serial, asset tag)
    try {
        $sys  = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
        $cps  = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop
        $r.System = [pscustomobject]@{
            Manufacturer    = $sys.Manufacturer
            Model           = $sys.Model
            SystemFamily    = $sys.SystemFamily
            SystemSKU       = $sys.SystemSKUNumber
            UUID            = $cps.UUID
            BiosVendor      = $bios.Manufacturer
            BiosVersion     = $bios.SMBIOSBIOSVersion
            BiosReleaseDate = $bios.ReleaseDate
            SerialNumber    = $bios.SerialNumber
            TotalPhysicalMemoryBytes = $sys.TotalPhysicalMemory
        }
    } catch { }

    # CPU detail
    try {
        $r.CPUs = @(Get-CimInstance Win32_Processor -ErrorAction Stop |
            Select-Object Name, Manufacturer, MaxClockSpeed, NumberOfCores, NumberOfLogicalProcessors, ProcessorId, Architecture, SocketDesignation)
    } catch { }

    # Memory modules
    try {
        $r.MemoryModules = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop |
            Select-Object @{n='CapacityGB';e={[math]::Round($_.Capacity/1GB,1)}}, Manufacturer, PartNumber, SerialNumber, Speed, ConfiguredClockSpeed, DeviceLocator, BankLabel, FormFactor)
    } catch { }

    # Logical disks (mounted volumes)
    try {
        $r.LogicalDisks = @(Get-CimInstance Win32_LogicalDisk -ErrorAction Stop |
            Select-Object DeviceID, DriveType, FileSystem, VolumeName,
                @{n='SizeGB';e={[math]::Round(($_.Size/1GB),1)}},
                @{n='FreeGB';e={[math]::Round(($_.FreeSpace/1GB),1)}},
                @{n='FreePct';e={ if ($_.Size) { [math]::Round(($_.FreeSpace/$_.Size)*100,1) } else { 0 } }},
                ProviderName)
    } catch { }

    # Physical disks
    try {
        $r.PhysicalDisks = @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop |
            Select-Object Model, InterfaceType, MediaType, FirmwareRevision, SerialNumber,
                @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, Partitions, Status)
    } catch { }

    # Volumes (broader than logical disks - includes mount-point-only volumes)
    try {
        $r.Volumes = @(Get-CimInstance Win32_Volume -ErrorAction Stop |
            Where-Object { $_.DriveType -in 2,3 } |
            Select-Object Name, Label, FileSystem, DriveLetter, DriveType,
                @{n='CapacityGB';e={[math]::Round($_.Capacity/1GB,1)}},
                @{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB,1)}}, BootVolume, SystemVolume)
    } catch { }

    # Network adapters - full config (only physical / IP-bound ones)
    try {
        $r.NetworkAdapters = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE' -ErrorAction Stop |
            Select-Object Description, MACAddress, IPAddress, IPSubnet, DefaultIPGateway,
                DNSServerSearchOrder, DNSDomain, DNSDomainSuffixSearchOrder,
                DHCPEnabled, DHCPServer, DHCPLeaseObtained, WINSPrimaryServer,
                IPConnectionMetric, ServiceName, SettingID)
    } catch { }
    try {
        $r.NetworkAdaptersAll = @(Get-CimInstance Win32_NetworkAdapter -ErrorAction Stop |
            Where-Object { $_.PhysicalAdapter -or $_.NetEnabled } |
            Select-Object Name, ProductName, MACAddress, AdapterType, Speed, NetEnabled, NetConnectionStatus, Manufacturer, ServiceName)
    } catch { }
    try {
        $r.HostsFile = (Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" -ErrorAction Stop |
            Where-Object { $_ -and ($_ -notmatch '^\s*#') -and ($_ -match '\S') })
    } catch { }

    # SMB shares offered by this host (if any)
    try {
        $r.Shares = @(Get-CimInstance Win32_Share -ErrorAction Stop |
            Where-Object { $_.Type -eq 0 -and $_.Name -notmatch '\$$' -or $_.Name -match '^(C\$|ADMIN\$|IPC\$)$' } |
            Select-Object Name, Path, Description, Type)
    } catch { }
    try {
        $r.MappedDrives = @(Get-CimInstance Win32_NetworkConnection -ErrorAction Stop |
            Select-Object LocalName, RemoteName, RemotePath, ConnectionState, UserName)
    } catch { }

    # Local users + local groups (Get-LocalUser is built-in on Win10+/Server2016+)
    try {
        if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
            $r.LocalUsers = @(Get-LocalUser -ErrorAction Stop |
                Select-Object Name, Enabled, PasswordRequired, PasswordExpires, PasswordLastSet, LastLogon, Description, FullName, AccountExpires, SID)
        }
    } catch { }
    try {
        if (Get-Command Get-LocalGroup -ErrorAction SilentlyContinue) {
            $groups = @(Get-LocalGroup -ErrorAction Stop)
            $r.LocalGroups = foreach ($grp in $groups) {
                $members = @()
                try { $members = @(Get-LocalGroupMember -Group $grp.Name -ErrorAction Stop | Select-Object Name, ObjectClass, PrincipalSource) } catch { }
                [pscustomobject]@{
                    Name        = $grp.Name
                    Description = $grp.Description
                    SID         = $grp.SID.Value
                    Members     = $members
                }
            }
        }
    } catch { }

    # All scheduled tasks (full list, not just consumer-experience subset)
    try {
        if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
            $r.ScheduledTasksAll = @(Get-ScheduledTask -ErrorAction Stop |
                Select-Object TaskPath, TaskName, State, Author,
                    @{n='LastRunTime';e={ try { (Get-ScheduledTaskInfo -TaskPath $_.TaskPath -TaskName $_.TaskName -ErrorAction SilentlyContinue).LastRunTime } catch { $null } }},
                    @{n='NextRunTime';e={ try { (Get-ScheduledTaskInfo -TaskPath $_.TaskPath -TaskName $_.TaskName -ErrorAction SilentlyContinue).NextRunTime } catch { $null } }})
        }
    } catch { }

    # Printers + print queues
    try {
        $r.Printers = @(Get-CimInstance Win32_Printer -ErrorAction Stop |
            Select-Object Name, ShareName, PortName, DriverName, Local, Network, Default, Status, WorkOffline)
    } catch { }

    # Windows roles / features (Server) and optional components (Client)
    try {
        if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
            $r.WindowsFeaturesInstalled = @(Get-WindowsFeature -ErrorAction Stop | Where-Object Installed |
                Select-Object Name, DisplayName, FeatureType, Path)
        }
    } catch { }
    try {
        if (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
            $r.OptionalFeaturesEnabled = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop |
                Where-Object { $_.State -eq 'Enabled' } |
                Select-Object FeatureName, State)
        }
    } catch { }
    try {
        if (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue) {
            $r.WindowsCapabilitiesInstalled = @(Get-WindowsCapability -Online -ErrorAction Stop |
                Where-Object { $_.State -eq 'Installed' } |
                Select-Object Name, State)
        }
    } catch { }

    # Environment variables (system-scope; user-scope varies per logon profile)
    try {
        $r.EnvironmentVariables = @(Get-CimInstance Win32_Environment -ErrorAction Stop |
            Select-Object Name, VariableValue, UserName, SystemVariable)
    } catch { }

    # Locale / time zone / region
    try {
        $r.TimeZone = (Get-TimeZone).Id
    } catch {
        try { $r.TimeZone = (Get-CimInstance Win32_TimeZone -ErrorAction Stop).StandardName } catch { }
    }
    try {
        $r.Culture = (Get-Culture).Name
    } catch { }

    # NTP / time source config
    try {
        $w32 = & w32tm /query /configuration 2>$null
        if ($w32) { $r.W32TimeConfig = ($w32 -join "`n") }
        $w32s = & w32tm /query /source 2>$null
        if ($w32s) { $r.W32TimeSource = ($w32s -join '; ').Trim() }
    } catch { }

    # Startup programs (HKLM Run + HKLM RunOnce + Common Startup folder)
    try {
        $startup = @()
        foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                       'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
                       'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
            try {
                $vals = Get-ItemProperty $k -ErrorAction Stop
                foreach ($p in $vals.PSObject.Properties) {
                    if ($p.Name -notmatch '^PS') {
                        $startup += [pscustomobject]@{ Source = $k; Name = $p.Name; Command = $p.Value }
                    }
                }
            } catch { }
        }
        $startupFolder = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'
        if (Test-Path $startupFolder) {
            foreach ($f in (Get-ChildItem $startupFolder -ErrorAction SilentlyContinue)) {
                $startup += [pscustomobject]@{ Source = '(Common Startup folder)'; Name = $f.Name; Command = $f.FullName }
            }
        }
        $r.StartupPrograms = $startup
    } catch { }

    # Office Click-to-Run config
    try {
        $oc = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction Stop
        $r.Office = [pscustomobject]@{
            ProductReleaseIds = $oc.ProductReleaseIds
            VersionToReport   = $oc.VersionToReport
            Platform          = $oc.Platform
            UpdateChannel     = $oc.UpdateChannel
            UpdateUrl         = $oc.UpdateUrl
            CDNBaseUrl        = $oc.CDNBaseUrl
            ClientCulture     = $oc.ClientCulture
            SharedComputerLicensing = $oc.SharedComputerLicensing
        }
    } catch { }

    # PowerShell + .NET runtime versions
    try {
        $r.PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        $r.PowerShellEdition = $PSVersionTable.PSEdition
    } catch { }
    try {
        $netVers = @()
        $base = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP'
        if (Test-Path $base) {
            Get-ChildItem $base -ErrorAction SilentlyContinue | ForEach-Object {
                $vp = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if ($vp.Version) { $netVers += [pscustomobject]@{ Key=$_.PSChildName; Version=$vp.Version; Release=$vp.Release } }
                Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
                    $sp = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                    if ($sp.Version) { $netVers += [pscustomobject]@{ Key=$_.PSChildName; Version=$sp.Version; Release=$sp.Release } }
                }
            }
        }
        $r.DotNetVersions = $netVers
    } catch { }

    # Hotfix history (full list, not just latest)
    try {
        $r.HotfixHistory = @(Get-HotFix -ErrorAction Stop |
            Sort-Object InstalledOn -Descending |
            Select-Object HotFixID, Description, InstalledOn, InstalledBy)
    } catch { }

    # Power plans
    try {
        $r.PowerPlans = @(Get-CimInstance -Namespace 'root\cimv2\power' -ClassName Win32_PowerPlan -ErrorAction Stop |
            Select-Object ElementName, IsActive, InstanceID)
    } catch { }

    # TPM state in-guest
    try {
        $tpm = Get-CimInstance -Namespace 'Root\CIMV2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
        if ($tpm) {
            $r.Tpm = [pscustomobject]@{
                IsActivated = $tpm.IsActivated_InitialValue
                IsEnabled   = $tpm.IsEnabled_InitialValue
                IsOwned     = $tpm.IsOwned_InitialValue
                SpecVersion = $tpm.SpecVersion
                ManufacturerVersion     = $tpm.ManufacturerVersion
                ManufacturerVersionInfo = $tpm.ManufacturerVersionInfo
            }
        }
    } catch { }

    # Antivirus product registered with Security Center (catches CrowdStrike etc.)
    try {
        $r.AntivirusProducts = @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop |
            Select-Object displayName, pathToSignedReportingExe, pathToSignedProductExe, productState, timestamp)
    } catch { }

    # Pending reboot state (canonical Microsoft sources)
    try {
        $pending = $false; $reasons = @()
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pending = $true; $reasons += 'CBS RebootPending' }
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pending = $true; $reasons += 'WindowsUpdate RebootRequired' }
        $rfo = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($rfo) { $pending = $true; $reasons += 'PendingFileRenameOperations' }
        $r.PendingReboot = $pending
        $r.PendingRebootReasons = $reasons
    } catch { }

    # Group Policy applied (gpresult /r); requires elevation, so may fail
    try {
        $gpr = & gpresult /r /scope:computer 2>$null
        if ($gpr) { $r.GpResult = ($gpr -join "`n") }
    } catch { }

    # Audit policy (auditpol /get); requires elevation
    try {
        $audit = & auditpol /get /category:* 2>$null
        if ($audit) { $r.AuditPolicy = ($audit -join "`n") }
    } catch { }

    # Event log size config (top 6 logs)
    try {
        $r.EventLogConfig = @(Get-CimInstance Win32_NTEventLogFile -ErrorAction Stop |
            Where-Object { $_.LogfileName -in @('Application','System','Security','Setup','Microsoft-Windows-PowerShell/Operational','Windows PowerShell') } |
            Select-Object LogfileName,
                @{n='MaxSizeMB';e={[math]::Round($_.MaxFileSize/1MB,1)}},
                @{n='UsedSizeMB';e={[math]::Round($_.FileSize/1MB,1)}},
                NumberOfRecords, OverwritePolicy)
    } catch { }

    # User profiles registered on the box (FSLogix-relevant)
    try {
        $r.UserProfiles = @(Get-CimInstance Win32_UserProfile -ErrorAction Stop |
            Where-Object { -not $_.Special } |
            Select-Object LocalPath, SID,
                @{n='LastUseTime';e={ if ($_.LastUseTime) { [datetime]::FromFileTime($_.LastUseTime) } else { $null } }},
                Loaded, RoamingConfigured, RoamingPath, Status)
    } catch { }

    # Drivers (top-level summary; full driver enum is heavy)
    try {
        $r.Drivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
            Where-Object { $_.DriverProviderName -and $_.DriverProviderName -ne 'Microsoft' } |
            Select-Object DeviceName, DriverProviderName, DriverVersion, DriverDate, DeviceClass)
    } catch { }

    return $r
}

function Test-WinRmAvailable {
<#
    Quick TCP probe for WinRM. Avoids the long Test-WSMan timeout when the
    target is on a network we cannot reach.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [int]$TimeoutMs = 1500
    )
    foreach ($port in 5985, 5986) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $async = $tcp.BeginConnect($ComputerName, $port, $null, $null)
            $ok = $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            if ($ok -and $tcp.Connected) { $tcp.Close(); return $true }
            $tcp.Close()
        } catch { }
    }
    return $false
}

function Get-GuestImageScan {
<#
    .SYNOPSIS
    Run an full introspection on a single VM. Returns a structured
    hashtable with VM metadata, optional in-guest data, and a Findings array
    where each entry is one best-practice violation.

    .PARAMETER Vm
    A PowerCLI VM object (Get-VM result) to scan.

    .PARAMETER Role
    'GoldDesktop' | 'RdshMaster' | 'AppVolumesPackaging' - determines which
    rules apply. Different roles have different sane-defaults (e.g., RDSH
    masters expect RDP enabled; gold desktops expect RDP disabled).

    .PARAMETER Credential
    Optional PSCredential for in-guest WinRM. Without it we run Tier 1 only.

    .PARAMETER WinRmTimeoutSeconds
    Total budget for the in-guest probe (TCP + Invoke-Command). Default 60s.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Vm,
        [Parameter(Mandatory)][ValidateSet('GoldDesktop','RdshMaster','AppVolumesPackaging')][string]$Role,
        [System.Management.Automation.PSCredential]$Credential,
        [int]$WinRmTimeoutSeconds = 60
    )

    $out = @{
        Machine        = $Vm.Name
        Role           = $Role
        VmHardware     = @{}
        Guest          = @{}
        Tier           = 'Tier1'
        Findings       = @()
    }

    # ---------- Tier 1: vCenter-side -----------------------------------
    $cfg = $Vm.ExtensionData.Config
    $devs = $cfg.Hardware.Device
    $hasTpm = ($devs | Where-Object { $_.GetType().Name -eq 'VirtualTPM' }) -ne $null
    $hasFloppy = ($devs | Where-Object { $_.GetType().Name -eq 'VirtualFloppy' }) -ne $null
    $hasSerial = ($devs | Where-Object { $_.GetType().Name -eq 'VirtualSerialPort' }) -ne $null
    $hasCdConn = ($devs | Where-Object { $_.GetType().Name -eq 'VirtualCdrom' -and $_.Connectable -and $_.Connectable.StartConnected })
    $secureBoot = ($cfg.BootOptions -and $cfg.BootOptions.EfiSecureBootEnabled)
    $firmware  = $cfg.Firmware
    $hwVersion = $Vm.HardwareVersion
    $vCpu      = $Vm.NumCpu
    $ramGB     = [math]::Round($Vm.MemoryGB, 0)
    $guestOsRaw = if ($Vm.Guest -and $Vm.Guest.OSFullName) { $Vm.Guest.OSFullName } else { $cfg.GuestFullName }
    $isWin11   = ($guestOsRaw -match 'Windows 11')
    $isWindows = ($guestOsRaw -match 'Windows')
    $vmIp      = if ($Vm.Guest -and $Vm.Guest.IPAddress) { @($Vm.Guest.IPAddress)[0] } else { '' }
    $toolsRunning = ($Vm.Guest -and $Vm.Guest.State -eq 'Running')

    # Extra vCenter-side inventory the plugin surfaces in the dump.
    $cluster = if ($Vm.VMHost -and $Vm.VMHost.Parent) { [string]$Vm.VMHost.Parent.Name } else { '' }
    $host_   = if ($Vm.VMHost) { [string]$Vm.VMHost.Name } else { '' }
    $dsList  = @()
    try { $dsList = @($Vm | Get-Datastore -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) } catch { }
    $snapCount = 0
    try { $snapCount = @($Vm | Get-Snapshot -ErrorAction SilentlyContinue).Count } catch { }
    $numNics  = @($devs | Where-Object { $_.GetType().Name -match 'VirtualEthernetCard|VirtualVmxnet|VirtualE1000|VirtualPCNet32' }).Count
    $numDisks = @($devs | Where-Object { $_.GetType().Name -eq 'VirtualDisk' }).Count

    $out.VmHardware = @{
        vCpu          = $vCpu
        RamGB         = $ramGB
        HardwareVer   = $hwVersion
        Firmware      = $firmware
        SecureBoot    = $secureBoot
        vTPM          = $hasTpm
        Floppy        = $hasFloppy
        Serial        = $hasSerial
        CdConnected   = [bool]$hasCdConn
        GuestOS       = $guestOsRaw
        IsWin11       = $isWin11
        IPAddress     = $vmIp
        ToolsRunning  = $toolsRunning
        PowerState    = [string]$Vm.PowerState
        Cluster       = $cluster
        VMHost        = $host_
        Datastores    = $dsList
        SnapshotCount = $snapCount
        NumNics       = $numNics
        NumDisks      = $numDisks
    }

    # ---------- Tier 2: in-guest probe ----------------------------------
    # Path A (preferred): WinRM PSSession - fast, full PowerShell.
    # Path B (fallback): Invoke-VMScript over VMware Tools - works even when
    # the guest NIC is disconnected (common Horizon parent VM pattern).
    # We try A first when an IP is reachable, fall back to B if Tools is
    # running and a credential is available.
    if ($Credential -and $toolsRunning) {
        $winrmTried = $false
        $winrmOK    = $false
        if ($vmIp) {
            $winrmTried = $true
            $reachable = Test-WinRmAvailable -ComputerName $vmIp -TimeoutMs 2000
            if (-not $reachable -and $Vm.Guest.HostName) {
                $reachable = Test-WinRmAvailable -ComputerName $Vm.Guest.HostName -TimeoutMs 2000
            }
            if ($reachable) {
                try {
                    $target = if ($Vm.Guest.HostName) { $Vm.Guest.HostName } else { $vmIp }
                    $session = New-PSSession -ComputerName $target -Credential $Credential -ErrorAction Stop
                    $remote = Invoke-Command -Session $session -ScriptBlock $Script:RemoteSb
                    Remove-PSSession $session -ErrorAction SilentlyContinue
                    $out.Guest = $remote
                    $out.Tier  = 'Tier2'
                    $winrmOK   = $true
                } catch {
                    $out.Guest.WinRmError = $_.Exception.Message
                }
            } else {
                $out.Guest.WinRmError = 'WinRM 5985/5986 unreachable; trying VMware Tools fallback.'
            }
        }
        # If WinRM was not tried (no IP, NIC disconnected) OR failed, try
        # Invoke-VMScript via VMware Tools. This works for parent VMs that
        # have NIC disabled per Horizon parent-VM hardening practice.
        if (-not $winrmOK) {
            try {
                # Wrap the probe scriptblock so its hashtable output comes
                # back as JSON via stdout - Invoke-VMScript only returns text.
                $sbText = $Script:RemoteSb.ToString()
                $wrappedScript = @"
`$ProgressPreference = 'SilentlyContinue'
`$result = & { $sbText } 2>`$null
'<<<JSON_BEGIN>>>'
`$result | ConvertTo-Json -Depth 6 -Compress
'<<<JSON_END>>>'
"@
                $vmScript = Invoke-VMScript -VM $Vm -ScriptText $wrappedScript -GuestCredential $Credential -ScriptType PowerShell -ErrorAction Stop
                $stdout = $vmScript.ScriptOutput
                if ($stdout -match '(?s)<<<JSON_BEGIN>>>\s*(.+?)\s*<<<JSON_END>>>') {
                    $jsonText = $Matches[1].Trim()
                    $remote = $jsonText | ConvertFrom-Json -ErrorAction Stop
                    # ConvertFrom-Json returns PSCustomObject; convert to hashtable
                    $remoteHt = @{}
                    foreach ($p in $remote.PSObject.Properties) { $remoteHt[$p.Name] = $p.Value }
                    $out.Guest = $remoteHt
                    $out.Tier  = 'Tier2-VMTools'
                } else {
                    $out.Guest.VMToolsError = "Invoke-VMScript returned no parseable output. Stdout: $($stdout.Substring(0, [Math]::Min(200, $stdout.Length)))"
                }
            } catch {
                $out.Guest.VMToolsError = "Invoke-VMScript failed: $($_.Exception.Message)"
            }
        }
    } elseif (-not $Credential) {
        $out.Guest.WinRmError = 'No PSCredential supplied; Tier 2 skipped.'
    }

    # ---------- Rule evaluation ----------------------------------------
    function _add { param($sev, $rule, $detail, $fix)
        $out.Findings += [pscustomobject]@{
            Machine  = $Vm.Name
            Role     = $Role
            Severity = $sev
            Rule     = $rule
            Detail   = $detail
            Fix      = $fix
        }
    }

    # ---- Hardware rules (always evaluable) ----
    switch ($Role) {
        'GoldDesktop' {
            if ($vCpu -gt 8)   { _add 'P2' 'Oversized vCPU on desktop master'    "Has $vCpu vCPU; desktops should typically be 2-4 (knowledge worker) or 4-8 (power user)." 'Right-size to desktop tier before snapshot + recompose.' }
            if ($ramGB -gt 32) { _add 'P1' 'Oversized RAM on desktop master'     "Has $ramGB GB RAM; desktops should typically be 4-8 GB (knowledge worker) or 16-32 GB (power user). 64+ GB is almost always a server template misclassified as a desktop." 'Right-size RAM to desktop tier; never deploy with > 32 GB on a generic IC pool.' }
        }
        'RdshMaster' {
            if ($vCpu -gt 16)  { _add 'P2' 'Oversized vCPU on RDSH master'       "Has $vCpu vCPU; RDSH masters are typically 4-12 vCPU sized for ~2-3 vCPU per session at 1:6 oversub." 'Right-size to expected RDSH session density.' }
            if ($ramGB -lt 16) { _add 'P3' 'Undersized RAM on RDSH master'       "Has $ramGB GB RAM; RDSH masters typically need 16-64 GB to host multi-user sessions." 'Increase RAM to expected tier.' }
        }
        'AppVolumesPackaging' {
            if ($vCpu -gt 4)   { _add 'P3' 'Oversized vCPU on AV packaging VM'    "Has $vCpu vCPU; packaging VMs are short-lived snapshots, 2-4 vCPU is plenty." 'Right-size; packaging VMs should be minimal.' }
            if ($ramGB -gt 16) { _add 'P3' 'Oversized RAM on AV packaging VM'     "Has $ramGB GB RAM; packaging VMs should be minimal." 'Right-size RAM.' }
        }
    }

    if ($hasFloppy) { _add 'P3' 'Legacy Floppy device' 'Virtual floppy attached.' 'Edit Settings -> remove Floppy device.' }
    if ($hasSerial) { _add 'P3' 'Legacy Serial port'   'Virtual serial port attached.' 'Edit Settings -> remove Serial device unless explicitly required.' }
    if ($hasCdConn) { _add 'P3' 'CD/DVD connected at boot' 'CD/DVD set to Connect at power on - blocks vMotion and clutters clones.' 'Edit Settings -> CD/DVD -> uncheck "Connect at power on".' }

    if ($isWin11 -and -not $hasTpm)    { _add 'P2' 'Win11 master missing vTPM'        'Win11 22H2+ requires TPM 2.0; clones will fail Win11 servicing.' 'Configure Standard Key Provider on vCenter, then VM -> Add Device -> Trusted Platform Module.' }
    if ($isWin11 -and -not $secureBoot) { _add 'P2' 'Win11 master missing Secure Boot' 'Win11 + vTPM requires Secure Boot enabled.' 'Edit Settings -> VM Options -> Boot Options -> enable Secure Boot.' }
    if ($isWin11 -and $firmware -and $firmware -ne 'efi') { _add 'P1' 'Win11 master on legacy BIOS' "Firmware = $firmware; Win11 requires UEFI." 'Cannot toggle BIOS->UEFI on a running Windows install. Plan reinstall.' }

    if ($cfg.Tools -and $cfg.Tools.SyncTimeWithHost) {
        _add 'P2' 'VMware Tools time-sync enabled' 'Tools time-sync overrides AD time hierarchy and breaks Kerberos when ESXi drifts.' 'Edit Settings -> VM Options -> Tools -> uncheck "Synchronize time with host".'
    }

    $hv = [int]($hwVersion -replace '[^0-9]','')
    if ($hv -lt 14) {
        _add 'P2' 'Hardware version below vmx-14' "Hardware = $hwVersion; vmx-14+ required for vTPM, Secure Boot." 'Power off, Compatibility -> Upgrade VM Compatibility -> >= vmx-19 recommended.'
    }

    # VM Encryption check
    $encrypted = $false
    try { if ($cfg.KeyId -and $cfg.KeyId.KeyId) { $encrypted = $true } } catch { }
    if ($encrypted) {
        _add 'P1' 'VM-level Encryption applied to master' 'VM Encryption breaks Instant Clone forking. vTPM is allowed; full VM Encryption is not.' 'Edit Settings -> VM Options -> Encryption -> change to Not encrypted.'
    }

    # Snapshots > 2
    $snaps = @(Get-Snapshot -VM $Vm -ErrorAction SilentlyContinue)
    if ($snaps.Count -gt 2) {
        _add 'P3' 'Excess snapshots on master' "$($snaps.Count) snapshots; best practice keeps active + 1 rollback." 'Consolidate older snapshots in vSphere Client.'
    }

    # ---- Tier 2 in-guest rules ----
    if ($out.Tier -in 'Tier2','Tier2-VMTools' -and $out.Guest) {
        $g = $out.Guest

        # OS patch level
        if ($g.LastHotfixInstalledOn) {
            $age = ((Get-Date) - [datetime]$g.LastHotfixInstalledOn).TotalDays
            if ($age -gt 60) {
                _add 'P2' 'Master patch lag' "Last hotfix installed $([int]$age) days ago ($($g.LastHotfixId))." 'Run Windows Update on the master, sysprep generalize, re-snapshot, recompose pool.'
            }
        }

        # BitLocker on Win11 master = anti-pattern (sealed keys do not fork)
        if ($Role -eq 'GoldDesktop' -and $g.BitLockerProtectionStatus -eq 1) {
            _add 'P1' 'BitLocker enabled on master volume' 'BitLocker key sealed to parent vTPM cannot be forked to clones - clones boot to BitLocker recovery prompt.' 'Run manage-bde -off C: in the master, wait for full decrypt, sysprep generalize, re-snapshot, recompose. Configure GPO to prevent BitLocker auto-enable on clones.'
        }

        # IPv6 disabled on AD-joined Windows = supported but not recommended
        if ($Role -eq 'GoldDesktop' -and $g.IPv6Enabled -eq $false -and $g.PartOfDomain) {
            _add 'P3' 'IPv6 disabled on domain-joined master' 'Microsoft does not recommend disabling IPv6 - some AD subsystems assume it is present.' 'Re-enable IPv6 unless an explicit security control mandates disablement.'
        }

        # FSLogix presence on gold desktop
        if ($Role -eq 'GoldDesktop' -and -not $g.FSLogixEnabled) {
            _add 'P3' 'FSLogix not configured on master' 'Profile container approach is the supported pattern for non-persistent VDI.' 'Install FSLogix Apps + configure registry under HKLM:\SOFTWARE\FSLogix\Profiles. Test profile mount on a pilot pool.'
        }

        # Defender exclusions for FSLogix paths
        if ($Role -eq 'GoldDesktop' -and $g.DefenderRealtime -and $g.FSLogixEnabled) {
            $hasFslExclusion = ($g.DefenderExclusionPath | Where-Object { $_ -match 'fslogix|profile' }).Count -gt 0
            if (-not $hasFslExclusion) {
                _add 'P2' 'Defender missing FSLogix exclusions' 'Defender real-time scan with no FSLogix exclusion = high CPU + slow profile mount.' 'Add path exclusions for FSLogix container storage + processes per Microsoft FSLogix AV guidance.'
            }
        }

        # Horizon Agent presence
        if ($Role -in 'GoldDesktop','RdshMaster' -and -not $g.HorizonAgentVersion) {
            _add 'P1' 'Horizon Agent not installed' 'Master image needs Horizon Agent for clones to broker correctly.' 'Install the Horizon Agent matching your CS version per Omnissa Components Matrix.'
        }

        # App Volumes Agent in correct mode
        if ($Role -eq 'AppVolumesPackaging' -and $g.AppVolumesAgentMode -ne 'ProvisioningMode') {
            _add 'P1' 'App Volumes Agent not in provisioning mode' "AgentMode = $($g.AppVolumesAgentMode); must be ProvisioningMode for capture VMs." 'Re-install Agent with provisioning flag, OR set HKLM:\SOFTWARE\CloudVolumes\Agent AgentMode = ProvisioningMode.'
        }
        if ($Role -in 'GoldDesktop','RdshMaster' -and $g.AppVolumesAgentMode -eq 'ProvisioningMode') {
            _add 'P1' 'App Volumes Agent in provisioning mode on a runtime master' "AgentMode = ProvisioningMode; runtime/end-user VMs must be RuntimeMode." 'Reinstall Agent without provisioning flag.'
        }

        # RDP state per role
        if ($Role -eq 'GoldDesktop' -and $g.RdpDenyTSConnections -eq $false) {
            _add 'P3' 'RDP enabled on desktop gold image' 'Desktop master images typically should not accept RDP - users connect via Blast/PCoIP through Horizon.' 'Disable RDP via System Properties -> Remote -> "Don''t allow" or via GPO.'
        }
        if ($Role -eq 'RdshMaster' -and $g.RdpDenyTSConnections -eq $true) {
            _add 'P1' 'RDP disabled on RDSH master' 'RDSH role requires RDP enabled - sessions broker via RDP under the hood.' 'Enable RDP and the Remote Desktop Services role/feature.'
        }

        # Bloat / consumer-experience tasks running
        $badTasks = @($g.ScheduledTasks | Where-Object { $_.State -ne 'Disabled' -and $_.Path -match 'Customer Experience|Application Experience|DiskDiagnostic|WinSAT' })
        if ($badTasks.Count -gt 0) {
            _add 'P3' 'Microsoft consumer-experience tasks enabled' "$($badTasks.Count) consumer-experience scheduled tasks still enabled - VDI optimization tool would disable these." 'Run VMware OS Optimization Tool (OSOT) against the master image to disable known-noisy scheduled tasks.'
        }

        # VMware Tools currency - hard to evaluate without target version, but
        # surface the version for the consultant.
        if (-not $g.VMwareToolsVersion) {
            _add 'P2' 'VMware Tools version unreadable' 'Could not read VMware Tools version from registry or vmtoolsd.exe - Tools may be missing or broken.' 'Reinstall VMware Tools on the master.'
        }
    }

    [pscustomobject]$out
}

Export-ModuleMember -Function Get-GuestImageScan, Test-WinRmAvailable
