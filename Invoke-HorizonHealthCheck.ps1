#Requires -Version 5.1
<#
.SYNOPSIS
    HealthCheckPS1 - plugin-based health-check runner for VMware/Omnissa Horizon.

.DESCRIPTION
    Connects to a Horizon Connection Server via REST, dot-sources every
    Plugins\**\*.ps1 in lexical order, captures emitted objects + the metadata
    each plugin sets ($Title, $Header, $Comments, $Display, $Severity,
    $Recommendation, $Author, $PluginVersion, $PluginCategory, $TableFormat),
    and produces a single HTML report.

    Severity bucketing (P1/P2/P3/Info) follows the VMware Health Analyzer
    (VHA) convention.

.PARAMETER Server
    Connection Server FQDN. Overrides $HVServer in GlobalVariables.ps1.

.PARAMETER Credential
    Horizon admin credentials. If omitted, you'll be prompted.

.PARAMETER Domain
    AD domain. Required if Credential.UserName is bare (no \\ or @).

.PARAMETER VCServer
    Optional vCenter FQDN for backing-infra plugins.

.PARAMETER VCCredential
    Optional vCenter credentials (defaults to $Credential).

.PARAMETER OutputPath
    Where to drop the HTML report.

.PARAMETER NoEmail
    Skip email even if $SendEmail is $true.

.PARAMETER PluginFilter
    Wildcard against plugin filename - useful for debugging one plugin.

.EXAMPLE
    .\Invoke-HorizonHealthCheck.ps1 -Server cs1.corp.local -Credential (Get-Credential)

.EXAMPLE
    .\Invoke-HorizonHealthCheck.ps1 -Server cs1.corp.local -PluginFilter "*Pool*"
#>
[CmdletBinding()]
param(
    [string]$Server,
    [pscredential]$Credential,
    [string]$Domain,
    [string]$VCServer,
    [pscredential]$VCCredential,
    # Optional Windows credential used by the gold-image / RDSH-master /
    # AppVolumes packaging-machine deep-scan plugins for Tier 2 in-guest
    # WinRM probes. Without this the plugins still run but only emit Tier 1
    # (vCenter-side) findings. Typical usage: a domain admin or a delegated
    # 'image-scan' account with WinRM permitted on the master VMs.
    [pscredential]$ImageScanCredential,
    # Optional human-readable customer / engagement label; flows into the
    # JSON sidecar and gets rendered on the AGI enriched report cover page.
    # Without this, only the vCenter / Horizon FQDN is shown.
    [string]$CustomerName,
    # Specialized-scope hints. Each plugin checks for its corresponding
    # $Global:* variable and skips gracefully when not set.
    [string[]]$ImprivataApplianceList,
    [string]$DEMConfigShare,
    [string]$ADForestFqdn,
    [pscredential]$ADCredential,
    [string[]]$AVPackagingVmHints,
    # Operator-supplied list of gold-image VM names (in addition to whatever
    # Horizon REST discovers from existing pools). Useful when Horizon is not
    # connected, or when scanning candidate masters that haven't been published yet.
    [string[]]$ManualGoldImageList,
    [switch]$MFAExternalProbe,
    [string]$OutputPath,
    [switch]$NoEmail,
    [string]$PluginFilter = '*.ps1',
    [switch]$SkipCertificateCheck,
    [switch]$Word,
    [switch]$ShowWord,
    [string]$DocAuthor = 'AuthorityGate'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }

# ---- Version + auto-update ------------------------------------------------
# Same auto-update pattern as Start-HorizonHealthCheckGUI.ps1: fetch the
# canonical VERSION from GitHub, compare, download release ZIP if newer,
# overlay the install in place, relaunch with the same arguments. Any
# network/file failure logs and falls through to running the local copy -
# never blocks startup.
$Script:HealthCheckVersion = '0.94.7'
$versionFile = Join-Path $root 'VERSION'
if (Test-Path $versionFile) {
    try { $v = (Get-Content $versionFile -Raw -ErrorAction Stop).Trim(); if ($v) { $Script:HealthCheckVersion = $v } } catch { }
}
$Script:UpdateChannel = @{
    GitHubOwner    = 'AuthorityGate'
    # v0.94.1 product rename - see Start-HorizonHealthCheckGUI.ps1 for the
    # rollover strategy. GitHub auto-redirects the old URL one more cycle.
    GitHubRepo     = 'Healthcheck'
    Tag            = 'v0.93.1-PreRelease'
    VersionFileUrl = 'https://raw.githubusercontent.com/AuthorityGate/Healthcheck/main/VERSION'
}

if ($env:HEALTHCHECK_NO_AUTOUPDATE -ne '1' -and -not $env:HEALTHCHECK_INSIDE_RELAUNCH) {
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        $remote = (Invoke-WebRequest -Uri $Script:UpdateChannel.VersionFileUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop).Content.Trim()
        $needs = $false
        try { $needs = ([version]$remote -gt [version]$Script:HealthCheckVersion) } catch { $needs = ($remote -and $remote -ne $Script:HealthCheckVersion) }
        if ($needs) {
            Write-Host "[update] Local v${Script:HealthCheckVersion} < remote v$remote - downloading update..." -ForegroundColor Yellow
            $zipName = "HealthCheckPS1-$($Script:UpdateChannel.Tag).zip"
            $assetUrl = "https://github.com/$($Script:UpdateChannel.GitHubOwner)/$($Script:UpdateChannel.GitHubRepo)/releases/download/$($Script:UpdateChannel.Tag)/$zipName"
            $stage = Join-Path $env:TEMP "HealthCheckPS1-update-$($PID)-$(Get-Random)"
            $zip = Join-Path $stage $zipName
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            Invoke-WebRequest -Uri $assetUrl -UseBasicParsing -OutFile $zip -TimeoutSec 120 -ErrorAction Stop
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $stage)
            $extracted = Join-Path $stage 'HealthCheckPS1'
            if (-not (Test-Path $extracted)) { $extracted = Get-ChildItem -Path $stage -Directory | Select-Object -First 1 -ExpandProperty FullName }
            if ($extracted -and (Test-Path $extracted)) {
                $copyExclude = @('.git','.github','.wrangler','memory','reports','Reports')
                Get-ChildItem -Path $extracted -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    if ($copyExclude -contains $_.Name) { return }
                    $dest = Join-Path $root $_.Name
                    if ($_.PSIsContainer) { Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force }
                    else { Copy-Item -Path $_.FullName -Destination $dest -Force }
                }
                # Anti-loop guard - force local VERSION to match remote so a
                # stale release asset can't trigger infinite re-download.
                try { Set-Content -Path (Join-Path $root 'VERSION') -Value $remote -Encoding UTF8 -ErrorAction Stop } catch { }
                Write-Host "[update] Updated ${Script:HealthCheckVersion} -> $remote. Relaunching..." -ForegroundColor Green
                Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
                # Re-launch in-process; pass the original parameters AND set
                # HEALTHCHECK_INSIDE_RELAUNCH so the new copy doesn't loop.
                $env:HEALTHCHECK_INSIDE_RELAUNCH = '1'
                $argList = @{}
                foreach ($k in $PSBoundParameters.Keys) { $argList[$k] = $PSBoundParameters[$k] }
                & $MyInvocation.MyCommand.Path @argList
                exit 0
            }
        } else {
            Write-Verbose "[update] Local v${Script:HealthCheckVersion} is current."
        }
    } catch {
        Write-Host "[update] Skipped (offline or failure): $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}

# ---- Load globals & modules -----------------------------------------------
. (Join-Path $root 'GlobalVariables.ps1')

if ($PSBoundParameters.ContainsKey('Server'))               { $HVServer = $Server }
if ($PSBoundParameters.ContainsKey('Domain'))               { $HVDomain = $Domain }
if ($PSBoundParameters.ContainsKey('SkipCertificateCheck')) { $HVSkipCertificateCheck = [bool]$SkipCertificateCheck }
if ($PSBoundParameters.ContainsKey('VCServer'))             { $VCServer = $VCServer }
if ($PSBoundParameters.ContainsKey('OutputPath'))           { $ReportPath = $OutputPath }

if (-not $HVServer -and -not $VCServer) {
    throw "Specify at least one target. Pass -Server (Horizon CS) and/or -VCServer (vCenter), or set `$HVServer / `$VCServer in GlobalVariables.ps1."
}
if ($HVServer -and -not $Credential) { $Credential = Get-Credential -Message "Horizon admin credentials for $HVServer" }
if (-not $VCCredential) { $VCCredential = $Credential }

# Surface ImageScanCredential as a global so the gold-image / RDSH-master /
# AppVolumes-packaging deep-scan plugins can do Tier 2 in-guest WinRM probes.
# Plugins read $Global:HVImageScanCredential and gracefully skip Tier 2 if
# it is not set.
if ($ImageScanCredential) {
    $Global:HVImageScanCredential = $ImageScanCredential
    Write-Host "[+] Image-scan credential supplied; gold-image plugins will run Tier 2 in-guest probes." -ForegroundColor Cyan
}
# Specialized-scope hints flow to plugins via $Global:*
if ($ImprivataApplianceList -and $ImprivataApplianceList.Count -gt 0) {
    $Global:ImprivataApplianceList = $ImprivataApplianceList
    Write-Host "[+] Imprivata appliance list supplied ($($ImprivataApplianceList.Count) URL(s))." -ForegroundColor Cyan
}
if ($DEMConfigShare)         { $Global:DEMConfigShare         = $DEMConfigShare;         Write-Host "[+] DEM config share supplied: $DEMConfigShare" -ForegroundColor Cyan }
if ($ADForestFqdn)           { $Global:ADForestFqdn           = $ADForestFqdn;           Write-Host "[+] AD forest target: $ADForestFqdn" -ForegroundColor Cyan }
if ($ADCredential)           { $Global:ADCredential           = $ADCredential;           Write-Host "[+] AD credential supplied: $($ADCredential.UserName)" -ForegroundColor Cyan }
if ($AVPackagingVmHints -and $AVPackagingVmHints.Count -gt 0) {
    $Global:AVPackagingVmHints = $AVPackagingVmHints
    Write-Host "[+] App Volumes packaging VM hints supplied ($($AVPackagingVmHints.Count) name(s))." -ForegroundColor Cyan
}
if ($MFAExternalProbe)       { $Global:MFAExternalProbe       = $true;                   Write-Host "[+] MFA external probe enabled." -ForegroundColor Cyan }
if ($ManualGoldImageList -and $ManualGoldImageList.Count -gt 0) {
    $Global:HVManualGoldImageList = $ManualGoldImageList
    Write-Host "[+] Manual gold image list: $($ManualGoldImageList.Count) VM(s)." -ForegroundColor Cyan
}

Add-Type -AssemblyName System.Web | Out-Null
Import-Module (Join-Path $root 'Modules\HorizonRest.psm1') -Force
Import-Module (Join-Path $root 'Modules\HtmlReport.psm1')  -Force
Import-Module (Join-Path $root 'Modules\Licensing.psm1')   -Force

# ---- License gate ---------------------------------------------------------
# Block execution unless a valid, non-expired, machine-bound license JWT is on
# disk. Use the GUI's License tab or Tools\Show-MachineFingerprint.ps1 +
# License.AuthorityGate.com to obtain one.
$Script:RunLicense = Get-AGLicense
if (-not $Script:RunLicense.Valid) {
    Write-Host ""
    Write-Host "  License required to run HealthCheckPS1." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Reason:  $($Script:RunLicense.Reason)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Get a license:" -ForegroundColor Cyan
    Write-Host "    1. Run .\Tools\Show-MachineFingerprint.ps1 (this machine)"
    Write-Host "    2. Submit at https://license.authoritygate.com/request"
    Write-Host "    3. Paste the emailed token into the GUI's License tab,"
    Write-Host "       OR write it to:"
    Write-Host "       $(Get-AGLicenseFilePath)"
    Write-Host ""
    throw "License invalid or missing. See messages above."
}
$licDays = if ($Script:RunLicense.ExpiresAt) { [math]::Round(($Script:RunLicense.ExpiresAt - (Get-Date)).TotalHours / 24, 1) } else { 0 }
Write-Host "[+] License: ACTIVE for $($Script:RunLicense.Claims.sub) ($licDays day(s) remaining)" -ForegroundColor Green

# Best-effort flush of queued telemetry from prior offline runs.
try { [void](Submit-AGUsageQueue) } catch { }

$Script:RunStartedAt = Get-Date
$Script:RunId        = [guid]::NewGuid().ToString()

# ---- Connect ---------------------------------------------------------------
$hvSession = $null
$hvSessions = @{}
$connAttempts = New-Object System.Collections.ArrayList
if ($HVServer) {
    # Horizon multi-pod: HVServer accepts comma/semicolon-separated FQDNs.
    $hvList = @($HVServer -split '[,;]\s*' | Where-Object { $_.Trim() })
    foreach ($hvOne in $hvList) {
        Write-Host "[+] Connecting to Horizon REST at $hvOne ..." -ForegroundColor Cyan
        $row = [pscustomobject]@{ Target='Horizon'; Server=$hvOne; Result='Failed'; ErrorMessage='' }
        try {
            $sess = Add-HVRestSession -Server $hvOne -Credential $Credential -Domain $HVDomain `
                -SkipCertificateCheck:$HVSkipCertificateCheck
            if ($sess) {
                $hvSessions[$hvOne] = $sess
                if (-not $hvSession) { $hvSession = $sess }
                $row.Result = 'Connected'
            }
        } catch {
            $row.ErrorMessage = $_.Exception.Message
            Write-Warning "Horizon connection failed for $hvOne`: $($_.Exception.Message)."
        }
        $null = $connAttempts.Add($row)
    }
} else {
    Write-Host "[i] No Horizon CS specified - Horizon plugins will skip." -ForegroundColor DarkGray
}

# Optional vCenter
$vcConnected = $false
if ($VCServer) {
    if (-not $VCCredential) { $VCCredential = Get-Credential -Message "vCenter credentials for $VCServer" }
    $row = [pscustomobject]@{ Target='vCenter'; Server=$VCServer; Result='Failed'; ErrorMessage='' }
    if (-not (Get-Module -ListAvailable -Name VMware.VimAutomation.Core)) {
        $row.ErrorMessage = "VMware PowerCLI is NOT installed. Install with: Install-Module -Name VMware.PowerCLI -Scope CurrentUser"
        Write-Warning "PowerCLI (VMware.VimAutomation.Core) not installed - vSphere plugins will skip."
    } else {
        Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
        if ($VCSkipCertificateCheck) {
            Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null
        }
        try {
            Connect-VIServer -Server $VCServer -Credential $VCCredential -ErrorAction Stop | Out-Null
            $vcConnected = $true
            $row.Result = 'Connected'
            Write-Host "[+] Connected to vCenter $VCServer." -ForegroundColor Cyan
        } catch {
            $row.ErrorMessage = $_.Exception.Message
            Write-Warning "vCenter connection failed: $($_.Exception.Message). vSphere plugins will skip."
        }
    }
    $null = $connAttempts.Add($row)
}

# ---- Plugin discovery ------------------------------------------------------
$pluginRoot = Join-Path $root 'Plugins'
$plugins = Get-ChildItem -Path $pluginRoot -Recurse -Filter $PluginFilter |
    Where-Object { -not $_.PSIsContainer -and $_.Extension -eq '.ps1' } |
    Sort-Object FullName

Write-Host "[+] Discovered $($plugins.Count) plugin(s)." -ForegroundColor Cyan

# Make a few useful variables visible to plugins
$Global:HVSession    = $hvSession
$Global:VCConnected  = $vcConnected

# ---- Run plugins ----------------------------------------------------------
$results = New-Object System.Collections.ArrayList

# Inject the connection-attempts table as the first plugin entry
if ($connAttempts.Count -gt 0) {
    $anyFailed = @($connAttempts | Where-Object { $_.Result -ne 'Connected' }).Count -gt 0
    $null = $results.Add([pscustomobject]@{
        Plugin='00 Connection Attempts'; Title='Connection Attempts'
        Header='[count] backend(s) attempted'
        Comments="Each target you supplied and the result of the connect attempt. If a row says 'Failed', the corresponding category is skipped wholesale."
        Display='Table'; Author='AuthorityGate'; PluginVersion=1.0
        PluginCategory='00 Initialize'
        Severity = if ($anyFailed) { 'P1' } else { 'Info' }
        Recommendation = if ($anyFailed) { "Resolve the failure: verify FQDN reachable, credentials valid, certificate trust (or pass -SkipCertificateCheck), and PowerCLI installed for vCenter. Re-run after fixing." } else { $null }
        TableFormat = @{ Result = { param($v,$row) if ($v -ne 'Connected') { 'bad' } else { 'ok' } } }
        Details = $connAttempts.ToArray(); Duration=0; Error=$null
    })
}

# NOTE: variable names use unusual prefixes ($_pluginSw, $_pluginErr) so
# dot-sourced plugins cannot accidentally shadow them. Past breakage: a
# plugin assigning $sw = $vDSwitchObject overwrote the runner's Stopwatch.
#
# Multi-pod: Horizon-scoped plugins run once per pod; non-Horizon plugins run once.
$horizonScopedCategories = @(
    '00 Initialize','10 Connection Servers','20 Cloud Pod Architecture',
    '30 Desktop Pools','40 RDS Farms','50 Machines','60 Sessions',
    '70 Events','80 Licensing and Certificates','90 Gateways',
    'B0 Imprivata','B1 Identity Manager','B2 Multi-Factor Auth'
)
$podKeys = if ($hvSessions -and $hvSessions.Count -gt 0) { @($hvSessions.Keys) } else { @($null) }
foreach ($p in $plugins) {
    $pluginCat = (Split-Path (Split-Path $p.FullName -Parent) -Leaf)
    $isHorizonPlugin = ($horizonScopedCategories -contains $pluginCat)
    $iterations = if ($isHorizonPlugin -and $podKeys.Count -gt 1) { $podKeys } else { @($podKeys[0]) }
    foreach ($podFqdn in $iterations) {
        if ($isHorizonPlugin -and $podFqdn) {
            try { Set-HVActiveSession -Server $podFqdn | Out-Null } catch { }
        }
        $_pluginSw   = [System.Diagnostics.Stopwatch]::StartNew()
        $Title = $Header = $Comments = $Display = $Author = $Recommendation = $Severity = $null
        $PluginVersion = 1.0
        $PluginCategory = $pluginCat
        $TableFormat = $null
        $_pluginErr = $null
        $details = @()
        $podSuffix = if ($isHorizonPlugin -and $podKeys.Count -gt 1 -and $podFqdn) { " [pod=$podFqdn]" } else { '' }
        Write-Host "  -> $($p.BaseName)$podSuffix" -NoNewline
        try {
            $details = @(. $p.FullName)
        } catch {
            $_pluginErr = $_.Exception.Message
            Write-Host "  [error] $_pluginErr" -ForegroundColor Red
        }
        $_pluginSw.Stop()
        if (-not $_pluginErr) {
            Write-Host ("  [{0,3} item(s), {1:0.00}s]" -f @($details).Count, $_pluginSw.Elapsed.TotalSeconds)
        }
        if ($isHorizonPlugin -and $podKeys.Count -gt 1 -and $podFqdn) {
            foreach ($d in @($details)) {
                if ($d -is [pscustomobject] -or $d -is [psobject]) {
                    if (-not $d.PSObject.Properties['Pod']) {
                        Add-Member -InputObject $d -NotePropertyName Pod -NotePropertyValue $podFqdn -Force
                    }
                }
            }
        }
        if (-not $Title)    { $Title    = $p.BaseName }
        if (-not $Display)  { $Display  = 'Table' }
        if (-not $Author)   { $Author   = 'AuthorityGate' }
        if (-not $Severity) { $Severity = 'Info' }
        # NOTE: $_perPluginTitle, not $reportTitle - PowerShell case-insensitive
        # variable names mean $reportTitle would clobber the global $ReportTitle.
        $_perPluginTitle = if ($isHorizonPlugin -and $podKeys.Count -gt 1 -and $podFqdn) { "$Title (pod: $podFqdn)" } else { $Title }
        $null = $results.Add([pscustomobject]@{
            Plugin          = $p.BaseName
            Title           = $_perPluginTitle
            Header          = $Header
            Comments        = $Comments
            Display         = $Display
            Author          = $Author
            PluginVersion   = $PluginVersion
            PluginCategory  = $PluginCategory
            Severity        = $Severity
            Recommendation  = $Recommendation
            TableFormat     = $TableFormat
            Details         = $details
            Duration        = $_pluginSw.Elapsed.TotalSeconds
            Error           = $_pluginErr
            Pod             = $podFqdn
        })
    }
}

# ---- Disconnect -----------------------------------------------------------
if ($hvSessions -and $hvSessions.Count -gt 0) { try { Disconnect-HVAllSessions } catch { } }
elseif ($hvSession) { try { Disconnect-HVRest } catch { } }
if ($vcConnected) { try { Disconnect-VIServer -Server $VCServer -Confirm:$false -Force | Out-Null } catch { } }

# ---- Render ---------------------------------------------------------------
if (-not (Test-Path $ReportPath)) { New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null }
$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
# Server label: prefer Horizon CS, fall back to vCenter when only vCenter was scanned
$serverLabel = if ($HVServer) { $HVServer } elseif ($VCServer) { $VCServer } else { 'unknown' }
$safeSrv   = $serverLabel -replace '[^a-zA-Z0-9.-]','_'
$reportFile = Join-Path $ReportPath "HealthCheck-$safeSrv-$stamp.html"

# Build the list of backends actually reached
$connected = @()
if ($hvSession)   { $connected += "Horizon ($HVServer)" }
if ($vcConnected) { $connected += "vCenter ($VCServer)" }

$html = New-HVReport -Results $results.ToArray() -Server $serverLabel -Title $ReportTitle -ConnectedBackends $connected
$html | Out-File -FilePath $reportFile -Encoding utf8

Write-Host "[+] HTML report written: $reportFile" -ForegroundColor Green

# ---- JSON export (sidecar, used by HealthCheckAGI for enriched reports) ---
$jsonFile = Join-Path $ReportPath "HealthCheck-$safeSrv-$stamp.json"
$jsonDoc = [pscustomobject]@{
    Schema        = 'HorizonHealthCheck/1'
    Generated     = (Get-Date).ToString('o')
    Server        = $serverLabel
    Title         = $ReportTitle
    CustomerName  = $CustomerName
    ImageScanTier = if ($ImageScanCredential) { 'Tier2' } else { 'Tier1' }
    ConnectedBackends = $connected
    Results       = $results.ToArray() | ForEach-Object {
        [pscustomobject]@{
            Plugin         = $_.Plugin
            Title          = $_.Title
            Header         = $_.Header
            Comments       = $_.Comments
            Display        = $_.Display
            Author         = $_.Author
            PluginVersion  = $_.PluginVersion
            PluginCategory = $_.PluginCategory
            Severity       = $_.Severity
            Recommendation = $_.Recommendation
            Details        = $_.Details
            Duration       = $_.Duration
            Error          = $_.Error
        }
    }
}
$jsonDoc | ConvertTo-Json -Depth 12 | Out-File -FilePath $jsonFile -Encoding utf8
Write-Host "[+] JSON sidecar written:  $jsonFile" -ForegroundColor Green

# ---- Run telemetry submission ---------------------------------------------
# Post run metadata to License.AuthorityGate.com. Failures queue locally for
# retry on the next successful run.
try {
    $tgts = @()
    foreach ($row in @($connAttempts.ToArray())) {
        if ($row.Result -eq 'Connected' -and $row.Target -and $row.Server) {
            $tgts += @{ type = [string]$row.Target; fqdn = [string]$row.Server }
        }
    }
    $sev = @{ P1=0; P2=0; P3=0; Info=0 }
    foreach ($r in $results) {
        $key = if ($r.Severity) { [string]$r.Severity } else { 'Info' }
        if (-not $sev.ContainsKey($key)) { $sev[$key] = 0 }
        $sev[$key] = $sev[$key] + 1
    }
    $completedAt = Get-Date
    $dur = [int]($completedAt - $Script:RunStartedAt).TotalSeconds
    $payload = @{
        run_id              = $Script:RunId
        machine_fp          = (Get-AGMachineFingerprint)
        hostname            = $env:COMPUTERNAME
        tool_version        = '2.0.0'
        started_at          = [int]([DateTimeOffset]$Script:RunStartedAt).ToUnixTimeSeconds()
        completed_at        = [int]([DateTimeOffset]$completedAt).ToUnixTimeSeconds()
        duration_seconds    = $dur
        doc_author          = $DocAuthor
        customer_engagement = if ($CustomerName) { $CustomerName } else { '' }
        targets             = $tgts
        plugin_count_total  = [int]$plugins.Count
        plugin_count_executed = [int]$plugins.Count
        findings_summary    = $sev
        report_filename     = (Split-Path -Leaf $jsonFile)
        report_size_bytes   = (Get-Item $jsonFile).Length
        status              = 'completed'
    }
    $tr = Submit-AGUsageEvent -Payload $payload
    if ($tr.Submitted) {
        Write-Host "[+] Run telemetry posted to License.AuthorityGate.com" -ForegroundColor Cyan
    } elseif ($tr.Queued) {
        Write-Host "[!] Telemetry queued locally (retry next run): $($tr.Error)" -ForegroundColor Yellow
    } else {
        Write-Host "[!] Telemetry not submitted: $($tr.Error)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[!] Telemetry submission threw: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ---- Optional Word doc  ---------------------------------------
$wordFile = $null
if ($Word) {
    Import-Module (Join-Path $root 'Modules\WordReport.psm1') -Force
    $wordFile = Join-Path $ReportPath "HealthCheck-$safeSrv-$stamp.docx"
    try {
        New-HVWordReport -Results $results.ToArray() -Server $serverLabel -Title $ReportTitle `
            -OutputFile $wordFile -Author $DocAuthor -ConnectedBackends $connected -ShowWord:$ShowWord | Out-Null
        Write-Host "[+] Word document written: $wordFile" -ForegroundColor Green
    } catch {
        Write-Warning "Word generation failed: $($_.Exception.Message). Verify Microsoft Word is installed locally."
    }
}

# ---- Email ----------------------------------------------------------------
if ($SendEmail -and -not $NoEmail -and $SmtpServer -and $EmailTo -and $EmailFrom) {
    try {
        $subj = $EmailSubject -f (Get-Date)
        $attach = @($reportFile)
        if ($wordFile -and (Test-Path $wordFile)) { $attach += $wordFile }
        Send-MailMessage -SmtpServer $SmtpServer -Port $SmtpPort -UseSsl:$SmtpUseSsl `
            -From $EmailFrom -To $EmailTo -Subject $subj -BodyAsHtml -Body $html `
            -Attachments $attach -ErrorAction Stop
        Write-Host "[+] Emailed report to $($EmailTo -join ', ')" -ForegroundColor Green
    } catch {
        Write-Warning "Email failed: $($_.Exception.Message)"
    }
}

# Return the path for chaining
$reportFile
