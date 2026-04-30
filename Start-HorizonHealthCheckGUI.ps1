# Requires -Version 5.1
<#
.SYNOPSIS
    GUI launcher for the AuthorityGate HealthCheck. No parameters required.

.DESCRIPTION
    5 tabbed connection panels: Horizon, vCenter, App Volumes, UAG, NSX.
    Each can be enabled or disabled independently. Plugins skip silently
    when the side they need is not connected.

    Non-secret state (server FQDNs, last folder, plugin selections) persists
    to %APPDATA%\HorizonHealthCheck\state.json. Passwords are NEVER stored.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
# State folder name kept stable across the v0.94.1 product rename
# (HorizonHealthCheck -> AuthorityGate HealthCheck) so existing operators
# don't lose their saved tab settings on upgrade. Display strings + URLs
# flipped; on-disk paths intentionally did not.
$stateDir  = Join-Path $env:APPDATA 'HorizonHealthCheck'
$stateFile = Join-Path $stateDir 'state.json'
if (-not (Test-Path $stateDir)) { New-Item -Path $stateDir -ItemType Directory -Force | Out-Null }

# ---- Crash trap -----------------------------------------------------------
# Anything that bubbles up uncaught past this point gets written to
# last-error.log next to the script AND echoed to the console BEFORE the
# process exits. Without this, RunGUI.cmd flashes closed on any startup
# failure and the operator has no way to know what blew up.
$Script:CrashLogPath = Join-Path $root 'last-error.log'
trap {
    $err = $_
    $msg = @"
=== HealthCheck startup crash $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===
Message: $($err.Exception.Message)
Type   : $($err.Exception.GetType().FullName)
Script : $($err.InvocationInfo.ScriptName)
Line # : $($err.InvocationInfo.ScriptLineNumber)
Line   : $($err.InvocationInfo.Line.Trim())
At col : $($err.InvocationInfo.OffsetInLine)

--- StackTrace ---
$($err.ScriptStackTrace)

--- Inner ---
$($err.Exception.InnerException)

--- Full record ---
$($err | Out-String)
"@
    try { Set-Content -Path $Script:CrashLogPath -Value $msg -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
    Write-Host $msg -ForegroundColor Red
    try {
        [System.Windows.Forms.MessageBox]::Show(
            "HealthCheck failed to start.`n`n$($err.Exception.Message)`n`nFull details written to:`n$Script:CrashLogPath",
            'AuthorityGate HealthCheck - Startup Error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } catch { }
    exit 1
}

# ---- Version tracking + auto-update ---------------------------------------
# Read local VERSION; if missing fall back to a hard-coded constant. Always
# expose $Script:HealthCheckVersion so the runspace + report header can
# include it. Auto-update is best-effort: any network/file error is logged
# and ignored - the user keeps running the local copy. We use a release-asset
# URL (GitHub Releases) so anonymous downloads don't hit the API rate limit.
$Script:HealthCheckVersion = '0.94.7'
$versionFile = Join-Path $root 'VERSION'
if (Test-Path $versionFile) {
    try { $v = (Get-Content $versionFile -Raw -ErrorAction Stop).Trim(); if ($v) { $Script:HealthCheckVersion = $v } } catch { }
}

$Script:UpdateChannel = @{
    GitHubOwner    = 'AuthorityGate'
    # v0.94.1 product rename: GitHub repo flipped from HorizonHealthCheck to
    # AuthorityGateHealthCheck. GitHub's automatic redirect keeps in-flight
    # v0.93.x and v0.94.0 clients downloading from the old URL for one more
    # update cycle before they pick up this new value, so the rollover is
    # single-cycle.
    GitHubRepo     = 'Healthcheck'
    Branch         = 'main'
    VersionFileUrl = 'https://raw.githubusercontent.com/AuthorityGate/Healthcheck/main/VERSION'
    SourceZipUrl   = 'https://codeload.github.com/AuthorityGate/Healthcheck/zip/refs/heads/main'
}

function Invoke-HealthCheckAutoUpdate {
    [CmdletBinding()]
    param(
        [string]$RootPath = $root,
        [string]$LocalVersion = $Script:HealthCheckVersion,
        [int]$TimeoutSec = 10,
        [switch]$Force
    )
    $report = [pscustomobject]@{
        Local = $LocalVersion; Remote = $null; Updated = $false; Error = $null; Action = 'Skipped (no update)'
    }
    # Fetch remote version. Honor TLS 1.2 explicitly (some downlevel boxes
    # default to TLS 1.0 still).
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        $remote = (Invoke-WebRequest -Uri $Script:UpdateChannel.VersionFileUrl -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop).Content.Trim()
        $report.Remote = $remote
    } catch {
        $report.Error = "Version probe failed: $($_.Exception.Message)"
        $report.Action = 'Skipped (offline)'
        return $report
    }

    # Compare versions. Lexical compare works for sane semver-ish tags
    # (0.93.1 < 0.93.2 < 0.94.0). For mixed letters fall through to "newer
    # iff strings differ".
    $needs = $false
    try {
        $lv = [version]$LocalVersion
        $rv = [version]$remote
        $needs = $rv -gt $lv
    } catch {
        $needs = ($remote -and $remote -ne $LocalVersion)
    }
    if (-not $needs -and -not $Force) {
        $report.Action = 'Up-to-date'
        return $report
    }

    # Download the live branch tarball (always matches main/VERSION). NOT a
    # release asset - those are cut once and rot out of sync with main.
    $stage = Join-Path $env:TEMP "HealthCheckPS1-update-$($PID)-$(Get-Random)"
    $zip = Join-Path $stage 'main.zip'
    try {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        Invoke-WebRequest -Uri $Script:UpdateChannel.SourceZipUrl -UseBasicParsing -OutFile $zip -TimeoutSec ([Math]::Max($TimeoutSec, 60)) -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $stage)
    } catch {
        $report.Error = "Download/extract failed: $($_.Exception.Message)"
        $report.Action = 'Skipped (download error - keeping local copy)'
        try { Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue } catch { }
        return $report
    }

    # codeload.github.com/<owner>/<repo>/zip/refs/heads/<branch> unpacks as
    # <stage>/<repo>-<branch>/* - find that first child directory dynamically.
    $extracted = Get-ChildItem -Path $stage -Directory | Where-Object { $_.Name -ne '__MACOSX' } | Select-Object -First 1 -ExpandProperty FullName
    if (-not $extracted -or -not (Test-Path $extracted)) {
        $report.Error = 'Extracted package layout unrecognized.'
        $report.Action = 'Skipped (bad package)'
        try { Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue } catch { }
        return $report
    }

    # SAFETY GATE: confirm the ZIP we just extracted actually contains code at
    # the version we promised the user. If the ZIP's VERSION disagrees with
    # the probed remote VERSION, refuse to swap files - that mismatch is the
    # exact pattern that caused the old release-pinned updater to overwrite
    # live plugins with year-old code.
    $zipVersion = $null
    try {
        $zipVersionFile = Join-Path $extracted 'VERSION'
        if (Test-Path $zipVersionFile) { $zipVersion = (Get-Content $zipVersionFile -Raw -ErrorAction Stop).Trim() }
    } catch { }
    if (-not $zipVersion) {
        $report.Error = 'Downloaded package has no VERSION file - refusing to swap files.'
        $report.Action = 'Skipped (package integrity check failed)'
        try { Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue } catch { }
        return $report
    }
    if ($zipVersion -ne $remote) {
        $report.Error = "Package VERSION ($zipVersion) does not match remote VERSION ($remote). Refusing to swap files to avoid a downgrade."
        $report.Action = 'Skipped (version mismatch)'
        try { Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue } catch { }
        return $report
    }

    # Copy over the local install in-place. Skip user state (state.json lives
    # in %APPDATA%, not in $root, so no risk there). We DO replace VERSION,
    # all Modules/*, all Plugins/**, top-level *.ps1, README, LICENSE.
    try {
        $copyExclude = @('.git','.github','.wrangler','memory','reports','Reports')
        Get-ChildItem -Path $extracted -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ($copyExclude -contains $_.Name) { return }
            $dest = Join-Path $RootPath $_.Name
            if ($_.PSIsContainer) {
                Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
            } else {
                Copy-Item -Path $_.FullName -Destination $dest -Force
            }
        }
        # No anti-loop clobber needed: the VERSION inside the ZIP is the
        # canonical value from main, and we already gated on that matching
        # the remote VERSION probe. The branch-tarball update path is
        # self-consistent by construction.
        $report.Updated = $true
        $report.Action = "Updated $LocalVersion -> $remote (relaunch required)"
    } catch {
        $report.Error = "Copy failed: $($_.Exception.Message)"
        $report.Action = 'Partial - some files may be in-flight; relaunch to verify.'
    } finally {
        try { Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue } catch { }
    }
    $report
}

# Run the update probe in foreground so a relaunch can happen before
# prereqs/starter dialog. Honor an opt-out env var so tests / dev sessions
# don't auto-update.
if ($env:HEALTHCHECK_NO_AUTOUPDATE -ne '1' -and -not $env:HEALTHCHECK_INSIDE_RELAUNCH) {
    $Script:UpdateReport = Invoke-HealthCheckAutoUpdate
    Write-Host "[update] Local v${Script:HealthCheckVersion} | Remote v$($Script:UpdateReport.Remote) | $($Script:UpdateReport.Action)" -ForegroundColor Cyan
    if ($Script:UpdateReport -and $Script:UpdateReport.Updated) {
        # Best-effort UI hint; if WinForms isn't available yet (rare) just print.
        try {
            [void][System.Windows.Forms.MessageBox]::Show(
                "HealthCheckPS1 was updated from $($Script:UpdateReport.Local) to $($Script:UpdateReport.Remote).`n`nRelaunching with the new version.",
                'AuthorityGate Update',
                'OK',
                'Information'
            )
        } catch {
            Write-Host "[update] $($Script:UpdateReport.Action)"
        }
        # Relaunch the (now-updated) script in a fresh process and exit cleanly.
        # Pass HEALTHCHECK_INSIDE_RELAUNCH so the new process skips its own
        # update probe (otherwise we could loop if the asset URL races the
        # VERSION URL during a partial deploy).
        $env:HEALTHCHECK_INSIDE_RELAUNCH = '1'
        $scriptPath = $MyInvocation.MyCommand.Path
        $hostExe = (Get-Process -Id $PID).Path
        if (-not $hostExe -or -not (Test-Path $hostExe)) { $hostExe = 'powershell.exe' }
        # Pre-format the -Command argument so Start-Process gets a complete
        # invocation; using $root (script-scope) for WorkingDirectory because
        # $RootPath is a function-only variable not in scope here.
        $relaunchCmd = "& '$scriptPath'"
        Start-Process -FilePath $hostExe `
            -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command',$relaunchCmd) `
            -WorkingDirectory $root
        Write-Host "[update] Relaunched new process. Exiting old PID=$PID." -ForegroundColor Green
        exit 0
    }
}

# ---- Module imports (MUST be at top - License tab built later in this -----
# script calls Get-AGLicense and Get-AGMachineFingerprint at construction
# time. If imports happen after that, those calls fail with 'term not
# recognized' and the License tab shows 'License module error' on launch.
# Surface load errors prominently - silent failure here breaks every license
# operation downstream, and an out-of-date Modules\Licensing.psm1 on a fresh
# clone is the most common gotcha.
$Script:LicensingModuleLoadError = $null
try {
    Import-Module (Join-Path $root 'Modules\CredentialProfiles.psm1') -Force -ErrorAction Stop
} catch {
    $Script:LicensingModuleLoadError = "CredentialProfiles.psm1 failed to load: $($_.Exception.Message)"
}
try {
    Import-Module (Join-Path $root 'Modules\Licensing.psm1') -Force -ErrorAction Stop
} catch {
    $Script:LicensingModuleLoadError = "Licensing.psm1 failed to load: $($_.Exception.Message)"
}

# ============================================================================
#  STARTER DIALOG  -  License + PSO acknowledgment + target picker
#  Runs BEFORE the main form. User must accept license, acknowledge PSO scope,
#  and tick at least one target. Returns a hashtable of selections, or $null
#  if the user cancels (in which case the script exits without launching the
#  main GUI). Whatever the user does NOT tick here is hard-disabled in the
#  main GUI - those tabs cannot be activated.
# ============================================================================
function Show-StarterDialog {
    param([string]$RootPath, [string]$LogoPath)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text          = "AuthorityGate HealthCheck v$Script:HealthCheckVersion - Welcome"
    $dlg.Size          = New-Object System.Drawing.Size(720, 860)
    $dlg.StartPosition = 'CenterScreen'
    $dlg.Font          = New-Object System.Drawing.Font('Segoe UI', 9)
    # Sizable + AutoScroll: jumpbox / RDP / 1366x768 users can drag-resize
    # OR the dialog auto-shows scrollbars when shorter than content height.
    # Maximize unlocked so users can full-screen it; min size keeps the
    # dialog usable - 600x540 fits buttons + license panel + at least 4
    # target checkboxes without scrolling.
    $dlg.FormBorderStyle = 'Sizable'
    $dlg.MaximizeBox   = $true
    $dlg.MinimizeBox   = $true
    $dlg.MinimumSize   = New-Object System.Drawing.Size(600, 540)
    $dlg.AutoScroll    = $true
    # Min content height = button row bottom (y=738) + padding. Default form
    # height (820 - ~30 title = 790 client) is 40 px taller, so no scrollbar
    # appears by default; only shows if the user shrinks the dialog.
    $dlg.AutoScrollMinSize = New-Object System.Drawing.Size(700, 800)
    $dlg.ShowInTaskbar = $true
    # Cap initial size to 95% of working area so the dialog never spawns
    # taller than the screen on a 1366x768 jumpbox.
    try {
        $workArea = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
        $maxW = [int]($workArea.Width  * 0.95)
        $maxH = [int]($workArea.Height * 0.95)
        if ($dlg.Size.Height -gt $maxH -or $dlg.Size.Width -gt $maxW) {
            $dlg.Size = New-Object System.Drawing.Size(([Math]::Min(720,$maxW)), ([Math]::Min(860,$maxH)))
        }
    } catch { }

    # Window icon (taskbar + title bar) - the AuthorityGate favicon.
    $iconPath = Join-Path $RootPath 'assets\AuthorityGate.ico'
    if (Test-Path $iconPath) {
        try { $dlg.Icon = New-Object System.Drawing.Icon($iconPath) } catch { }
    }

    # ---- Top branding strip with white-to-dark-gold gradient
    $head = New-Object System.Windows.Forms.Panel
    $head.Dock = 'Top'
    $head.Height = 80
    # Paint handler draws a multi-stop gradient (white -> cream -> gold ->
    # dark gold) plus a 3px dark-gold rule along the bottom. Repaints
    # automatically on resize.
    $head.Add_Paint({
        param($sender, $e)
        $rect = $sender.ClientRectangle
        if ($rect.Width -le 0 -or $rect.Height -le 0) { return }
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $rect,
            [System.Drawing.Color]::White,
            [System.Drawing.Color]::FromArgb(138, 105, 20),
            [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
        $blend = New-Object System.Drawing.Drawing2D.ColorBlend
        $blend.Colors    = @(
            [System.Drawing.Color]::White,
            [System.Drawing.Color]::FromArgb(251, 246, 232),
            [System.Drawing.Color]::FromArgb(212, 168, 42),
            [System.Drawing.Color]::FromArgb(138, 105, 20)
        )
        $blend.Positions = @([single]0.0,[single]0.28,[single]0.70,[single]1.0)
        $brush.InterpolationColors = $blend
        $e.Graphics.FillRectangle($brush, $rect)
        $brush.Dispose()
        # Bottom 3px dark-gold border
        $borderBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(107, 82, 16))
        $e.Graphics.FillRectangle($borderBrush, [System.Drawing.Rectangle]::new($rect.X, $rect.Bottom - 3, $rect.Width, 3))
        $borderBrush.Dispose()
    })
    $dlg.Controls.Add($head)

    if ($LogoPath -and (Test-Path $LogoPath)) {
        $logo = New-Object System.Windows.Forms.PictureBox
        # Logo at x=20 (was 14) for clear left margin; anchor Top|Left
        # keeps it pinned when the dialog is resized so it never drifts
        # off-screen.
        $logo.Location = New-Object System.Drawing.Point(20, 8)
        $logo.Size     = New-Object System.Drawing.Size(64, 64)
        $logo.SizeMode = 'Zoom'
        $logo.BackColor = [System.Drawing.Color]::Transparent
        $logo.Anchor   = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
        $logo.ImageLocation = $LogoPath
        $head.Controls.Add($logo)
    }
    $hT = New-Object System.Windows.Forms.Label
    $hT.Text = 'AuthorityGate HealthCheck'
    $hT.Location = New-Object System.Drawing.Point(96, 12)
    $hT.Size = New-Object System.Drawing.Size(500, 28)
    $hT.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $hT.ForeColor = [System.Drawing.Color]::Black
    $hT.BackColor = [System.Drawing.Color]::Transparent
    $hT.Anchor   = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $head.Controls.Add($hT)
    $hS = New-Object System.Windows.Forms.Label
    $hS.Text = "v$Script:HealthCheckVersion - review the license, acknowledge use, and pick targets."
    $hS.Location = New-Object System.Drawing.Point(96, 44)
    $hS.Size = New-Object System.Drawing.Size(620, 22)
    $hS.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $hS.ForeColor = [System.Drawing.Color]::FromArgb(28, 30, 33)
    $hS.BackColor = [System.Drawing.Color]::Transparent
    $head.Controls.Add($hS)

    # ---- License box (summary + link to full LICENSE)
    $lblLic = New-Object System.Windows.Forms.Label
    $lblLic.Text = 'License terms (AuthorityGate Source-Available License v1.0):'
    $lblLic.Location = New-Object System.Drawing.Point(20, 92)
    $lblLic.Size = New-Object System.Drawing.Size(660, 20)
    $lblLic.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $dlg.Controls.Add($lblLic)

    $licBox = New-Object System.Windows.Forms.TextBox
    $licBox.Multiline = $true
    $licBox.ScrollBars = 'Vertical'
    $licBox.ReadOnly  = $true
    $licBox.Location = New-Object System.Drawing.Point(20, 114)
    $licBox.Size     = New-Object System.Drawing.Size(660, 200)
    $licBox.Font     = New-Object System.Drawing.Font('Consolas', 8.5)
    $licBox.BackColor = [System.Drawing.Color]::White
    $licBox.Text = @"
AuthorityGate HealthCheck is published under the AuthorityGate Source-Available
License v1.0. This is NOT an open-source license - the source is published for
transparency, security audit, and inspection. Use, modification, and
distribution are restricted. Full text in the LICENSE file in the project root.

GRANT (summary - read the full LICENSE for the binding terms):
  - View / read the source code in this repository.
  - Execute the Software ONLY when you hold a valid, non-expired License
    Token issued by AuthorityGate, Inc. This applies to every execution
    without exception (evaluation, training, lab, internal IT, customer
    engagement). There is no grace period and no key-less execution path.
  - Modify the Software for your own internal use; do not redistribute the
    modified Software; notify architect@authoritygate.com of the modification.

PSO Customers receive License Tokens at no additional cost as part of their
engagement. Non-PSO commercial users contact architect@authoritygate.com
for a commercial license; short-window evaluation tokens may be issued at
AuthorityGate's sole discretion.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND. AuthorityGate,
Inc. is not liable for operational impact, downtime, data loss, or any other
consequence of using this tool.

ADDITIONAL OPERATOR GUIDANCE
============================
1. This tool is intended for use within an authorized AuthorityGate
   Professional Services Organization (PSO) engagement.
2. Reports produced by this tool are CONFIDENTIAL to the customer
   environment scanned. The operator is responsible for handling them
   accordingly.
3. The tool performs READ-ONLY operations against the configured
   backends (Horizon, vCenter, App Volumes, UAG, NSX, AD, ADAM, etc.).
   No setting, policy, or runtime state is modified. Results are written
   locally to the chosen output folder; only license-telemetry metadata
   (run timestamps, plugin counts, finding totals) is uploaded to
   license.authoritygate.com.

For commercial licensing or any use not permitted under Section 2 of the
LICENSE, contact: architect@authoritygate.com

By clicking 'Continue' below, you confirm:
  -  You have read and agree to the AuthorityGate Source-Available License v1.0.
  -  You acknowledge the AuthorityGate operator-guidance clauses above.
  -  You have authorization to assess the targets you select.
  -  You hold a valid, non-expired License Token for this execution.
"@
    $dlg.Controls.Add($licBox)

    $lnkFullLic = New-Object System.Windows.Forms.LinkLabel
    $lnkFullLic.Text = 'Open full LICENSE file ->'
    $lnkFullLic.Location = New-Object System.Drawing.Point(20, 320)
    $lnkFullLic.Size = New-Object System.Drawing.Size(220, 18)
    $licPath = Join-Path $RootPath 'LICENSE'
    $lnkFullLic.Add_LinkClicked({ if (Test-Path $licPath) { Start-Process $licPath } else { Start-Process 'https://www.apache.org/licenses/LICENSE-2.0' } }.GetNewClosure())
    $dlg.Controls.Add($lnkFullLic)

    $lnkRepo = New-Object System.Windows.Forms.LinkLabel
    $lnkRepo.Text = 'Repo: github.com/AuthorityGate/Healthcheck'
    $lnkRepo.Location = New-Object System.Drawing.Point(260, 320)
    $lnkRepo.Size = New-Object System.Drawing.Size(420, 18)
    $lnkRepo.Add_LinkClicked({ Start-Process 'https://github.com/AuthorityGate/Healthcheck' })
    $dlg.Controls.Add($lnkRepo)

    # ---- Acceptance checkboxes
    $cbAccept = New-Object System.Windows.Forms.CheckBox
    $cbAccept.Text = 'I have read and agree to the MIT license + AuthorityGate operator-guidance clauses above.'
    $cbAccept.Location = New-Object System.Drawing.Point(20, 348)
    $cbAccept.Size     = New-Object System.Drawing.Size(660, 24)
    $dlg.Controls.Add($cbAccept)

    $cbPSO = New-Object System.Windows.Forms.CheckBox
    $cbPSO.Text = 'I confirm this run is part of an authorized AuthorityGate PSO engagement.'
    $cbPSO.Location = New-Object System.Drawing.Point(20, 374)
    $cbPSO.Size     = New-Object System.Drawing.Size(660, 24)
    $dlg.Controls.Add($cbPSO)

    # ---- Target picker
    $grpTgt = New-Object System.Windows.Forms.GroupBox
    $grpTgt.Text = ' What do you want to check? '
    $grpTgt.Location = New-Object System.Drawing.Point(20, 408)
    # Group height accommodates 10 checkboxes (Horizon, vCenter, Nutanix,
    # AppVol, UAG, NSX, DEM, vIDM, UEM, AD) at 24 px stride starting at y=46.
    # Last checkbox (AD) tops at y=262, autoNote follows at y=290.
    # NOTE: GroupBox inherits from Control, not ScrollableControl, so it has
    # no AutoScroll property. The parent dialog already has AutoScroll=$true,
    # so when the window is shorter than the GroupBox the FORM scrolls.
    $grpTgt.Size     = New-Object System.Drawing.Size(660, 330)
    $grpTgt.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $dlg.Controls.Add($grpTgt)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Tick a target = those checks WILL run. Unticked targets are HARD-DISABLED for this session.'
    $hint.Location = New-Object System.Drawing.Point(14, 22)
    $hint.Size     = New-Object System.Drawing.Size(640, 18)
    $hint.Font     = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Italic)
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $grpTgt.Controls.Add($hint)

    $cbHV  = New-Object System.Windows.Forms.CheckBox
    $cbHV.Text  = 'Horizon Connection Server'
    $cbHV.Location = New-Object System.Drawing.Point(20, 46)
    $cbHV.Size     = New-Object System.Drawing.Size(620, 22)
    $cbHV.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
    $grpTgt.Controls.Add($cbHV)

    $cbVC  = New-Object System.Windows.Forms.CheckBox
    $cbVC.Text  = 'vCenter Server  (full vSphere / vSAN / Lifecycle / Hardware checks)'
    $cbVC.Location = New-Object System.Drawing.Point(20, 70)
    $cbVC.Size     = New-Object System.Drawing.Size(620, 22)
    $cbVC.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
    $grpTgt.Controls.Add($cbVC)

    # Nutanix sits next to vCenter (both are hypervisor managers).
    $cbNTNX = New-Object System.Windows.Forms.CheckBox
    $cbNTNX.Text = 'Nutanix Prism Central / Element (AHV hypervisor)'
    $cbNTNX.Location = New-Object System.Drawing.Point(20, 94)
    $cbNTNX.Size     = New-Object System.Drawing.Size(620, 22)
    $cbNTNX.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
    $grpTgt.Controls.Add($cbNTNX)

    $cbAV  = New-Object System.Windows.Forms.CheckBox
    $cbAV.Text  = 'App Volumes Manager'
    $cbAV.Location = New-Object System.Drawing.Point(20, 118)
    $cbAV.Size     = New-Object System.Drawing.Size(620, 22)
    $cbAV.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
    $grpTgt.Controls.Add($cbAV)

    $cbUAG = New-Object System.Windows.Forms.CheckBox
    $cbUAG.Text = 'Unified Access Gateway (UAG)'
    $cbUAG.Location = New-Object System.Drawing.Point(20, 142)
    $cbUAG.Size     = New-Object System.Drawing.Size(620, 22)
    $cbUAG.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
    $grpTgt.Controls.Add($cbUAG)

    $cbNSX = New-Object System.Windows.Forms.CheckBox
    $cbNSX.Text = 'NSX Manager'
    $cbNSX.Location = New-Object System.Drawing.Point(20, 166)
    $cbNSX.Size     = New-Object System.Drawing.Size(620, 22)
    $cbNSX.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
    $grpTgt.Controls.Add($cbNSX)

    $cbDEM = New-Object System.Windows.Forms.CheckBox
    $cbDEM.Text = 'Dynamic Environment Manager (DEM / FlexEngine) shares + agent'
    $cbDEM.Location = New-Object System.Drawing.Point(20, 190)
    $cbDEM.Size     = New-Object System.Drawing.Size(620, 22)
    $cbDEM.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
    $grpTgt.Controls.Add($cbDEM)

    $cbVIDM = New-Object System.Windows.Forms.CheckBox
    $cbVIDM.Text = 'Workspace ONE Access (vIDM) - SAML federation, directory bindings, app catalog'
    $cbVIDM.Location = New-Object System.Drawing.Point(20, 214)
    $cbVIDM.Size     = New-Object System.Drawing.Size(620, 22)
    $cbVIDM.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
    $grpTgt.Controls.Add($cbVIDM)

    $cbUEM = New-Object System.Windows.Forms.CheckBox
    $cbUEM.Text = 'Workspace ONE UEM (AirWatch) - device inventory, OG hierarchy, profiles, apps'
    $cbUEM.Location = New-Object System.Drawing.Point(20, 238)
    $cbUEM.Size     = New-Object System.Drawing.Size(620, 22)
    $cbUEM.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
    $grpTgt.Controls.Add($cbUEM)

    # Active Directory: multi-forest probing - configured via the AD tab on
    # the main form (per-row DC + Forest + credential profile).
    $cbAD = New-Object System.Windows.Forms.CheckBox
    $cbAD.Text = 'Active Directory (forests / domains / sites / DCs / replication / FSMO / GPO / KRBTGT / delegation)'
    $cbAD.Location = New-Object System.Drawing.Point(20, 262)
    $cbAD.Size     = New-Object System.Drawing.Size(620, 22)
    $cbAD.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
    $grpTgt.Controls.Add($cbAD)

    # Auto-discovery footnote: components that piggyback on the targets
    # checked above and do NOT need their own input field. Spelling these
    # out here saves the operator from looking for a non-existent tab.
    $autoNote = New-Object System.Windows.Forms.Label
    $autoNote.Text = 'Auto-discovered when Horizon is checked: Connection Servers (replicas), Cloud Pod Federation (CPA), Enrollment Servers (True SSO), Pods, Sites, vCenter registrations, RADIUS/SAML/Smart-Card authenticators, Helpdesk, Network Ranges, Access Groups, Persistent Disks, App Pools, Farms, Pools, Sessions. Auto-discovered when vCenter is checked: every cluster + host + datastore + alarm + event. Optional add-ons are configured via "Configure Specialized Scopes..." on the main form.'
    $autoNote.Location = New-Object System.Drawing.Point(20, 290)
    $autoNote.Size     = New-Object System.Drawing.Size(620, 36)
    $autoNote.Font     = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Italic)
    $autoNote.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $grpTgt.Controls.Add($autoNote)

    # ---- Buttons
    # Buttons sit on a single row directly below the target group box (which
    # ends at y=688). Both right-aligned, anchored Bottom|Right so resizing
    # the dialog keeps them visible. Form height (780) leaves ~50px breathing
    # room below the row at y=702 so the buttons are never clipped.
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Location = New-Object System.Drawing.Point(420, 752)
    $btnCancel.Size     = New-Object System.Drawing.Size(108, 36)
    $btnCancel.DialogResult = 'Cancel'
    $btnCancel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $dlg.Controls.Add($btnCancel)
    $dlg.CancelButton = $btnCancel

    $btnContinue = New-Object System.Windows.Forms.Button
    $btnContinue.Text = 'Continue'
    $btnContinue.Location = New-Object System.Drawing.Point(540, 752)
    $btnContinue.Size     = New-Object System.Drawing.Size(146, 36)
    $btnContinue.BackColor = [System.Drawing.Color]::FromArgb(10, 61, 98)
    $btnContinue.ForeColor = [System.Drawing.Color]::White
    $btnContinue.FlatStyle = 'Flat'
    $btnContinue.Enabled = $false
    $btnContinue.DialogResult = 'OK'
    $btnContinue.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $dlg.Controls.Add($btnContinue)
    $dlg.AcceptButton = $btnContinue
    $dlg.CancelButton = $btnCancel

    # Continue gated on: license + PSO + at least one target
    $reEvalScript = {
        $anyTarget = $cbHV.Checked -or $cbVC.Checked -or $cbAV.Checked -or $cbUAG.Checked -or $cbNSX.Checked -or $cbDEM.Checked -or $cbNTNX.Checked -or $cbVIDM.Checked -or $cbUEM.Checked -or $cbAD.Checked
        $btnContinue.Enabled = ($cbAccept.Checked -and $cbPSO.Checked -and $anyTarget)
    }
    foreach ($cb in @($cbAccept, $cbPSO, $cbHV, $cbVC, $cbAV, $cbUAG, $cbNSX, $cbDEM, $cbNTNX, $cbVIDM, $cbUEM, $cbAD)) {
        $cb.Add_CheckedChanged($reEvalScript)
    }

    $result = $dlg.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }
    [pscustomobject]@{
        UseHorizon = $cbHV.Checked
        UseVCenter = $cbVC.Checked
        UseAV      = $cbAV.Checked
        UseUAG     = $cbUAG.Checked
        UseNSX     = $cbNSX.Checked
        UseDEM     = $cbDEM.Checked
        UseNTNX    = $cbNTNX.Checked
        UseVIDM    = $cbVIDM.Checked
        UseUEM     = $cbUEM.Checked
        UseAD      = $cbAD.Checked
    }
}

# ---- Prerequisite auto-bootstrap (BEFORE starter dialog) -----------------
# Run Test-Prerequisites.ps1; if anything required is missing, prompt the
# user to launch the bundled Install-Prerequisites.ps1. We don't auto-install
# without confirmation - the install is ~150MB of PowerCLI from the internet.
function Test-AndInstallPrereqs {
    param([string]$RootPath)
    $testScript = Join-Path $RootPath 'Tools\Test-Prerequisites.ps1'
    $instScript = Join-Path $RootPath 'Tools\Install-Prerequisites.ps1'
    if (-not (Test-Path $testScript) -or -not (Test-Path $instScript)) {
        return $true   # tooling missing; assume operator knows what they're doing
    }
    $status = & $testScript
    if ($status.AllRequiredOk) { return $true }

    $missingList = ($status.Missing -join ', ')
    $msg = @"
Missing prerequisites: $missingList

AuthorityGate HealthCheck can install them for you (no Administrator required - they
install into your user profile).

  - VMware.PowerCLI is ~150 MB from www.powershellgallery.com.
  - Takes 5-10 minutes the first time.

Click YES to run the installer now (it streams progress to a console window),
or NO to exit so you can install manually.
"@
    $r = [System.Windows.Forms.MessageBox]::Show($msg, 'AuthorityGate HealthCheck - Prerequisites',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }

    # Launch installer in a visible console window so the user can see progress.
    $shell = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
    $psi = Start-Process -FilePath $shell `
        -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',$instScript) `
        -PassThru -Wait
    if ($psi.ExitCode -ne 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Prerequisite install reported exit code $($psi.ExitCode). Review the console window for the explicit error, fix the issue, and re-launch RunGUI.cmd.",
            'AuthorityGate HealthCheck - Install Failed',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return $false
    }
    # Re-test after install
    $status = & $testScript
    if (-not $status.AllRequiredOk) {
        [System.Windows.Forms.MessageBox]::Show(
            ("Install ran but verification still reports missing: " + ($status.Missing -join ', ') +
             ". Close all PowerShell windows and re-launch RunGUI.cmd."),
            'AuthorityGate HealthCheck - Verification Failed',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    return $true
}
if (-not (Test-AndInstallPrereqs -RootPath $root)) { return }

# Run starter dialog. If user cancels, exit immediately.
$selection = Show-StarterDialog -RootPath $root -LogoPath (Join-Path $root 'assets\AuthorityGate.png')
if (-not $selection) { return }

# ---- Default + persisted state -------------------------------------------
# All target checkboxes default to OFF. The user MUST tick a tab (or use a
# quick-select button) to activate it. This prevents accidental Horizon scans
# during a vCenter-only assessment.
$state = @{
    UseHorizon = $false; HVServer = ''; HVUser = ''; HVDomain = ''; HVSkipCert = $false
    UseVCenter = $false; VCServer = ''; VCUser = ''; VCSkipCert = $false
    UseAV      = $false; AVServer = ''; AVUser = ''; AVSkipCert = $false; AVPackagingVms = ''
    UseNTNX    = $false; NTNXServer = ''; NTNXUser = 'admin'; NTNXPort = 9440; NTNXSkipCert = $false
    UseUAG     = $false; UAGServer = ''; UAGUser = 'admin'; UAGPort = 9443; UAGSkipCert = $false
    UseNSX     = $false; NSXServer = ''; NSXUser = 'admin'; NSXSkipCert = $false
    UseVIDM    = $false; VIDMServer = ''; VIDMClientId = ''; VIDMTenantPath = '/SAAS'; VIDMSkipCert = $false
    UseUEM     = $false; UEMServer = '';  UEMUser = ''; UEMSkipCert = $false
    UseVEEAM   = $false; VeeamServer = ''; VeeamUser = ''; VeeamPort = 9419; VeeamSkipCert = $false
    UseFSLogix = $false; FSLogixProfileShare = ''; FSLogixCloudShare = ''
    UseCA      = $false; CAServerList = ''
    UseSQL     = $false; SQLServerList = ''
    UseEntra   = $false; EntraSyncServer = ''
    UseAD      = $false; ADForests  = @()    # @(@{Forest='forest.example';CredProfile='AD - svc'},...)
    OutputPath = (Join-Path $root 'Reports')
    GenerateHtml = $true; GenerateWord = $false; ShowWord = $false
    DocAuthor  = 'AuthorityGate'
    DisabledPlugins = @()
}
if (Test-Path $stateFile) {
    try {
        $loaded = Get-Content $stateFile -Raw | ConvertFrom-Json
        foreach ($k in $loaded.PSObject.Properties.Name) { $state[$k] = $loaded.$k }
    } catch { }
}
function Global:Save-State { ($state | ConvertTo-Json -Depth 4) | Out-File -FilePath $stateFile -Encoding utf8 }

# ---- Apply starter-dialog selection -------------------------------------
# Whatever the user picked on the starter is force-set; whatever they did NOT
# pick is force-cleared and that tab is hard-disabled in the main GUI for
# this session, so it cannot be activated by accident.
# Port defaults guard - if state.json was written with 0 / null / wrong type
# (older versions of this script may have written the wrong shape), force
# the canonical port back so the textbox in the tab is never blank.
if (-not $state.UAGPort  -or [int]$state.UAGPort  -le 0) { $state.UAGPort  = 9443 }
if (-not $state.NTNXPort -or [int]$state.NTNXPort -le 0) { $state.NTNXPort = 9440 }

$state.UseHorizon = [bool]$selection.UseHorizon
$state.UseVCenter = [bool]$selection.UseVCenter
$state.UseAV      = [bool]$selection.UseAV
$state.UseUAG     = [bool]$selection.UseUAG
$state.UseNSX     = [bool]$selection.UseNSX
$state.UseDEM     = [bool]$selection.UseDEM
$state.UseNTNX    = [bool]$selection.UseNTNX
$state.UseVIDM    = [bool]$selection.UseVIDM
$state.UseUEM     = [bool]$selection.UseUEM
$state.UseAD      = [bool]$selection.UseAD
if (-not $state.PSObject.Properties['DEMConfigShare'])  { $state | Add-Member NoteProperty DEMConfigShare ''  -Force }
if (-not $state.PSObject.Properties['DEMArchiveShare']) { $state | Add-Member NoteProperty DEMArchiveShare '' -Force }
if (-not $state.PSObject.Properties['DEMAgentTarget'])  { $state | Add-Member NoteProperty DEMAgentTarget ''  -Force }

function New-Label($text, $x, $y, $w=120) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x,$y); $l.Size = New-Object System.Drawing.Size($w, 22)
    $l
}
function New-TextBox($x, $y, $w=260, [string]$value='') {
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point($x,$y); $tb.Size = New-Object System.Drawing.Size($w, 22)
    $tb.Text = $value
    $tb
}
function New-CheckBox($text, $x, $y, $w=240, $checked=$false) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $text; $cb.Location = New-Object System.Drawing.Point($x,$y); $cb.Size = New-Object System.Drawing.Size($w, 22)
    $cb.Checked = [bool]$checked
    $cb
}
function New-PanelControls($parent, $hasUserDomain=$true) {
    $ctrls = @{}
    $ctrls.Use = New-CheckBox 'Connect to this target' 14 14 320 $false
    $parent.Controls.Add($ctrls.Use)

    $parent.Controls.Add((New-Label 'Server FQDN' 14 50))
    $ctrls.Server = New-TextBox 140 48
    $parent.Controls.Add($ctrls.Server)

    $parent.Controls.Add((New-Label 'Username' 14 80))
    $ctrls.User = New-TextBox 140 78
    $parent.Controls.Add($ctrls.User)

    # Credential profile picker - small dropdown button to the right of the
    # Username field. Click -> menu of saved profiles -> selecting one
    # populates User + Pass + (Domain when present).
    $ctrls.UseProfile = New-Object System.Windows.Forms.Button
    $ctrls.UseProfile.Text = 'Profile...'
    $ctrls.UseProfile.Location = New-Object System.Drawing.Point(410, 78)
    $ctrls.UseProfile.Size     = New-Object System.Drawing.Size(80, 22)
    $ctrls.UseProfile.FlatStyle = 'Flat'
    $ctrls.UseProfile.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $parent.Controls.Add($ctrls.UseProfile)

    $parent.Controls.Add((New-Label 'Password' 14 110))
    $ctrls.Pass = New-TextBox 140 108
    $ctrls.Pass.UseSystemPasswordChar = $true
    $parent.Controls.Add($ctrls.Pass)

    # Save-current-creds-as-profile button next to the Password field
    $ctrls.SaveProfile = New-Object System.Windows.Forms.Button
    $ctrls.SaveProfile.Text = 'Save...'
    $ctrls.SaveProfile.Location = New-Object System.Drawing.Point(410, 108)
    $ctrls.SaveProfile.Size     = New-Object System.Drawing.Size(80, 22)
    $ctrls.SaveProfile.FlatStyle = 'Flat'
    $ctrls.SaveProfile.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $parent.Controls.Add($ctrls.SaveProfile)

    if ($hasUserDomain) {
        $parent.Controls.Add((New-Label 'Domain' 14 140))
        $ctrls.Domain = New-TextBox 140 138
        $parent.Controls.Add($ctrls.Domain)
        $ctrls.SkipCert = New-CheckBox 'Skip cert validation (lab)' 140 168 230 $false
    } else {
        $ctrls.SkipCert = New-CheckBox 'Skip cert validation (lab)' 140 138 230 $false
    }
    $parent.Controls.Add($ctrls.SkipCert)

    # Test button: top-right corner of the panel, next to the 'Connect to ...'
    # checkbox. This row is always free regardless of which tab adds extra
    # fields below (Tenant API key on UEM, domain on Horizon, port on UAG,
    # Packaging VMs on AppVol). Previously placed at (326, 168) and crashed
    # into the Tenant-API-key textbox on the UEM tab and similar locations
    # on other extended tabs.
    $ctrls.Test = New-Object System.Windows.Forms.Button
    $ctrls.Test.Text = 'Test'
    $ctrls.Test.Location = New-Object System.Drawing.Point(508, 10)
    $ctrls.Test.Size     = New-Object System.Drawing.Size(80, 26)
    $ctrls.Test.BackColor = [System.Drawing.Color]::FromArgb(10, 61, 98)
    $ctrls.Test.ForeColor = [System.Drawing.Color]::White
    $ctrls.Test.FlatStyle = 'Flat'
    $parent.Controls.Add($ctrls.Test)

    $ctrls
}

# ---- Lightweight modal helpers (defined BEFORE any handler that calls them
# so the function is in the script scope at click time, regardless of where
# the closure was registered). Read-NameDialog returns a single text value;
# Read-PassphraseDialog returns a SecureString.
function Global:Read-NameDialog {
    param([string]$Title='Input', [string]$Prompt='Enter value', [string]$DefaultValue='')
    $d = New-Object System.Windows.Forms.Form
    $d.Text = $Title; $d.Size = New-Object System.Drawing.Size(500, 180)
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'Sizable'; $d.MaximizeBox = $true; $d.AutoScroll = $true; $d.MinimumSize = New-Object System.Drawing.Size(360, 140)
    $d.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Prompt; $lbl.Location = New-Object System.Drawing.Point(14, 14); $lbl.Size = New-Object System.Drawing.Size(460, 40)
    $d.Controls.Add($lbl)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(14, 60); $tb.Size = New-Object System.Drawing.Size(460, 22)
    $tb.Text = $DefaultValue
    $d.Controls.Add($tb)
    $script:nameResult = $null
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'OK'; $btnOk.Location = New-Object System.Drawing.Point(304, 100); $btnOk.Size = New-Object System.Drawing.Size(80, 28)
    $btnOk.Add_Click({ $script:nameResult = $tb.Text; $d.DialogResult = 'OK'; $d.Close() })
    $d.Controls.Add($btnOk); $d.AcceptButton = $btnOk
    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = 'Cancel'; $btnNo.Location = New-Object System.Drawing.Point(394, 100); $btnNo.Size = New-Object System.Drawing.Size(80, 28)
    $btnNo.Add_Click({ $d.DialogResult = 'Cancel'; $d.Close() })
    $d.Controls.Add($btnNo); $d.CancelButton = $btnNo
    [void]$d.ShowDialog()
    return $script:nameResult
}

function Global:Read-PassphraseDialog {
    param([string]$Title='Passphrase', [string]$Prompt='Enter passphrase')
    $d = New-Object System.Windows.Forms.Form
    $d.Text = $Title; $d.Size = New-Object System.Drawing.Size(460, 180)
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'Sizable'; $d.MaximizeBox = $true; $d.AutoScroll = $true; $d.MinimumSize = New-Object System.Drawing.Size(360, 140)
    $d.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Prompt; $lbl.Location = New-Object System.Drawing.Point(14, 14); $lbl.Size = New-Object System.Drawing.Size(420, 40)
    $d.Controls.Add($lbl)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(14, 60); $tb.Size = New-Object System.Drawing.Size(420, 22)
    $tb.UseSystemPasswordChar = $true
    $d.Controls.Add($tb)
    $script:ppResult = $null
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'OK'; $btnOk.Location = New-Object System.Drawing.Point(264, 100); $btnOk.Size = New-Object System.Drawing.Size(80, 28)
    $btnOk.Add_Click({
        if ($tb.Text) { $script:ppResult = (ConvertTo-SecureString $tb.Text -AsPlainText -Force) }
        $d.DialogResult = 'OK'; $d.Close()
    })
    $d.Controls.Add($btnOk)
    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = 'Cancel'; $btnNo.Location = New-Object System.Drawing.Point(354, 100); $btnNo.Size = New-Object System.Drawing.Size(80, 28)
    $btnNo.Add_Click({ $d.DialogResult = 'Cancel'; $d.Close() })
    $d.Controls.Add($btnNo)
    [void]$d.ShowDialog()
    return $script:ppResult
}

# ---- Profile picker / saver wireup --------------------------------------
# Called once per target tab to wire its UseProfile + SaveProfile buttons to
# the credential store. Filter by profile Type via the $TypeFilter array
# (e.g. ('Domain','vCenterSSO') for vCenter; ('Local','Domain') for Horizon).
function Register-ProfileButtons($ctrls, [string[]]$TypeFilter, [string]$SuggestedType, [string]$Label) {
    $ctrls.UseProfile.Add_Click({
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $profiles = @(Get-AGCredentialProfile | Sort-Object Name)
        # Filter by type, but always include 'Other' as a safety net
        $matching = @($profiles | Where-Object { -not $TypeFilter -or $TypeFilter -contains $_.Type -or $_.Type -eq 'Other' })
        if ($matching.Count -eq 0) {
            $mi = $menu.Items.Add("(no profiles - click 'Manage Credentials...' to add)")
            $mi.Enabled = $false
        } else {
            foreach ($p in $matching) {
                $name = $p.Name
                $userDisplay = $p.UserName
                $mi = $menu.Items.Add("$name  -  $userDisplay  [$($p.Type)]")
                $mi.Tag = $name
                $mi.Add_Click({
                    param($s,$e)
                    $sel = Get-AGCredentialProfile -Name $s.Tag
                    if (-not $sel) { return }
                    try {
                        $cred = Get-AGCredentialAsPSCredential -Name $s.Tag
                    } catch {
                        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Profile decrypt failed', 'OK', 'Error') | Out-Null
                        return
                    }
                    $ctrls.User.Text = $cred.UserName
                    $ctrls.Pass.Text = $cred.GetNetworkCredential().Password
                    # Auto-fill Domain if the tab has it and the username has a domain qualifier
                    if ($ctrls.ContainsKey('Domain') -and -not $ctrls.Domain.Text) {
                        if ($cred.UserName -match '\\') { $ctrls.Domain.Text = ($cred.UserName -split '\\')[0] }
                        elseif ($cred.UserName -match '@') { $ctrls.Domain.Text = ($cred.UserName -split '@')[1] }
                    }
                }.GetNewClosure())
            }
            $menu.Items.Add('-') | Out-Null
        }
        $miMgr = $menu.Items.Add('Manage Credentials...')
        $miMgr.Add_Click({ Show-CredentialProfileDialog })
        $menu.Show($ctrls.UseProfile, 0, $ctrls.UseProfile.Height)
    }.GetNewClosure())

    $ctrls.SaveProfile.Add_Click({
        if (-not $ctrls.User.Text -or -not $ctrls.Pass.Text) {
            [System.Windows.Forms.MessageBox]::Show('Type Username + Password first, then click Save... to store them as a named profile.', 'Save profile', 'OK', 'Information') | Out-Null
            return
        }
        $defaultName = "$Label - $($ctrls.User.Text)"
        $name = Read-NameDialog -Title 'Save credential profile' -Prompt 'Save these credentials as a named profile. Pick a unique name:' -DefaultValue $defaultName
        if (-not $name) { return }
        $sec = ConvertTo-SecureString $ctrls.Pass.Text -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($ctrls.User.Text, $sec)
        Set-AGCredentialProfile -Name $name -Credential $cred -Type $SuggestedType -Notes "Saved from $Label tab" | Out-Null
        [System.Windows.Forms.MessageBox]::Show("Saved profile '$name'. Available next time from the Profile... button on any tab.", 'Profile saved', 'OK', 'Information') | Out-Null
    }.GetNewClosure())
}

# ---- Form ----------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "AuthorityGate HealthCheck v${Script:HealthCheckVersion} - github.com/AuthorityGate/Healthcheck"
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
# Default size targets 1080+ height screens. Jumpboxes / seamless RDP often
# only have 768 of vertical real estate, so we ALSO:
#   - drop MinimumSize to 720x620 (so users can shrink below the default)
#   - enable AutoScroll (so when the window is shorter than the content,
#     scrollbars appear inside the form instead of clipping content off
#     the bottom of the screen with no way to reach Run / Open Last Report)
#   - cap the initial size to 90% of the working area so we never spawn the
#     form bigger than the actual screen
$form.Size = New-Object System.Drawing.Size(900, 950)
$form.MinimumSize = New-Object System.Drawing.Size(720, 640)
$form.AutoScroll = $true
$form.AutoScrollMinSize = New-Object System.Drawing.Size(880, 930)
# Compute the target monitor's working area, clamp the form size to fit,
# then explicitly position the form fully on-screen. CenterScreen alone
# is not enough on some multi-monitor / RDP / Teams-shared setups where
# the OS hands us negative-coordinate origins or partial screens.
try {
    $workArea = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
    $maxW = [int]($workArea.Width  * 0.95)
    $maxH = [int]($workArea.Height * 0.95)
    $newW = [Math]::Min(900, $maxW)
    $newH = [Math]::Min(950, $maxH)
    if ($newW -lt 720) { $newW = 720 }
    if ($newH -lt 640) { $newH = 640 }
    $form.Size = New-Object System.Drawing.Size($newW, $newH)
    # Manual position - center on this monitor, then clamp so neither
    # edge falls past the working area.
    $form.StartPosition = 'Manual'
    $cx = $workArea.X + [int](($workArea.Width  - $newW) / 2)
    $cy = $workArea.Y + [int](($workArea.Height - $newH) / 2)
    if ($cx -lt $workArea.X) { $cx = $workArea.X }
    if ($cy -lt $workArea.Y) { $cy = $workArea.Y }
    $form.Location = New-Object System.Drawing.Point($cx, $cy)
} catch { }

# Window icon (taskbar + title bar) - the AuthorityGate favicon.
$iconPath = Join-Path $root 'assets\AuthorityGate.ico'
if (Test-Path $iconPath) {
    try { $form.Icon = New-Object System.Drawing.Icon($iconPath) } catch { }
}

# ---- Branding banner (top strip) - white-to-dark-gold gradient ----------
$banner = New-Object System.Windows.Forms.Panel
$banner.Location = New-Object System.Drawing.Point(0, 0)
$banner.Size     = New-Object System.Drawing.Size($form.ClientSize.Width, 64)
$banner.Dock     = 'Top'
# Paint handler: multi-stop gradient (white -> cream -> gold -> dark gold)
# with a 3px dark-gold rule along the bottom. Re-paints on resize.
$banner.Add_Paint({
    param($sender, $e)
    $rect = $sender.ClientRectangle
    if ($rect.Width -le 0 -or $rect.Height -le 0) { return }
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::White,
        [System.Drawing.Color]::FromArgb(138, 105, 20),
        [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend
    $blend.Colors    = @(
        [System.Drawing.Color]::White,
        [System.Drawing.Color]::FromArgb(251, 246, 232),
        [System.Drawing.Color]::FromArgb(212, 168, 42),
        [System.Drawing.Color]::FromArgb(138, 105, 20)
    )
    $blend.Positions = @([single]0.0,[single]0.28,[single]0.70,[single]1.0)
    $brush.InterpolationColors = $blend
    $e.Graphics.FillRectangle($brush, $rect)
    $brush.Dispose()
    $borderBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(107, 82, 16))
    $e.Graphics.FillRectangle($borderBrush, [System.Drawing.Rectangle]::new($rect.X, $rect.Bottom - 3, $rect.Width, 3))
    $borderBrush.Dispose()
})
# Resize -> repaint so the gradient stretches with the form
$banner.Add_Resize({ param($s,$e) $s.Invalidate() })
$form.Controls.Add($banner)

# Logo on the left (transparent over white gradient stop). x=20 gives
# clearer left margin so the logo is never clipped by a narrow form or a
# screen-share frame; Anchor pins it to top-left on resize. BringToFront
# guarantees the banner gradient never paints over the logo.
$logoPath = Join-Path $root 'assets\AuthorityGate.png'
if (Test-Path $logoPath) {
    $logoBox = New-Object System.Windows.Forms.PictureBox
    $logoBox.Location = New-Object System.Drawing.Point(20, 4)
    $logoBox.Size     = New-Object System.Drawing.Size(56, 56)
    $logoBox.SizeMode = 'Zoom'
    $logoBox.BackColor = [System.Drawing.Color]::Transparent
    $logoBox.Anchor   = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $logoBox.ImageLocation = $logoPath
    $banner.Controls.Add($logoBox)
    $logoBox.BringToFront()
}

# Title in the middle (black for charcoal contrast across the gradient)
$bannerTitle = New-Object System.Windows.Forms.Label
$bannerTitle.Text     = 'AuthorityGate HealthCheck'
$bannerTitle.Location = New-Object System.Drawing.Point(78, 8)
$bannerTitle.Size     = New-Object System.Drawing.Size(440, 26)
$bannerTitle.Font     = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$bannerTitle.ForeColor = [System.Drawing.Color]::Black
$bannerTitle.BackColor = [System.Drawing.Color]::Transparent
$banner.Controls.Add($bannerTitle)

$bannerTag = New-Object System.Windows.Forms.Label
$bannerTag.Text     = 'GUI-driven health check for Horizon, App Volumes, DEM, UAG, NSX, vSphere & vSAN'
$bannerTag.Location = New-Object System.Drawing.Point(78, 36)
$bannerTag.Size     = New-Object System.Drawing.Size(540, 18)
$bannerTag.Font     = New-Object System.Drawing.Font('Segoe UI', 8)
$bannerTag.ForeColor = [System.Drawing.Color]::FromArgb(28, 30, 33)
$bannerTag.BackColor = [System.Drawing.Color]::Transparent
$banner.Controls.Add($bannerTag)

# Links on the right (dark on the gold side of the gradient)
$lnkGit = New-Object System.Windows.Forms.LinkLabel
$lnkGit.Text     = 'github.com/AuthorityGate/Healthcheck'
$lnkGit.Location = New-Object System.Drawing.Point(560, 10)
$lnkGit.Size     = New-Object System.Drawing.Size(320, 18)
$lnkGit.LinkColor   = [System.Drawing.Color]::Black
$lnkGit.ActiveLinkColor = [System.Drawing.Color]::FromArgb(60, 40, 0)
$lnkGit.LinkBehavior = 'HoverUnderline'
$lnkGit.BackColor = [System.Drawing.Color]::Transparent
$lnkGit.TextAlign = 'MiddleRight'
$lnkGit.Add_LinkClicked({ Start-Process 'https://github.com/AuthorityGate/Healthcheck' })
$banner.Controls.Add($lnkGit)

$lnkWeb = New-Object System.Windows.Forms.LinkLabel
$lnkWeb.Text     = 'www.authoritygate.com'
$lnkWeb.Location = New-Object System.Drawing.Point(560, 32)
$lnkWeb.Size     = New-Object System.Drawing.Size(320, 18)
$lnkWeb.LinkColor   = [System.Drawing.Color]::Black
$lnkWeb.ActiveLinkColor = [System.Drawing.Color]::FromArgb(60, 40, 0)
$lnkWeb.LinkBehavior = 'HoverUnderline'
$lnkWeb.BackColor = [System.Drawing.Color]::Transparent
$lnkWeb.TextAlign = 'MiddleRight'
$lnkWeb.Add_LinkClicked({ Start-Process 'https://www.authoritygate.com' })
$banner.Controls.Add($lnkWeb)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(12, 76)
$tabs.Size     = New-Object System.Drawing.Size(870, 240)
$form.Controls.Add($tabs)

# ----------------------------------------------------------------------------
# License tab - first tab so it is visible on launch.
# Status display, machine fingerprint, Request and Activate buttons.
# Pre-run gate (in btnRun click) blocks Run Health Check when no valid license.
# ----------------------------------------------------------------------------
$tabLic = New-Object System.Windows.Forms.TabPage
$tabLic.Text = 'License'
$tabs.TabPages.Add($tabLic)

$lblLicStatus = New-Object System.Windows.Forms.Label
$lblLicStatus.Location = New-Object System.Drawing.Point(12, 12)
$lblLicStatus.Size     = New-Object System.Drawing.Size(840, 30)
$lblLicStatus.Font     = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$tabLic.Controls.Add($lblLicStatus)

$lblLicEmail = New-Object System.Windows.Forms.Label
$lblLicEmail.Location = New-Object System.Drawing.Point(12, 46)
$lblLicEmail.Size     = New-Object System.Drawing.Size(840, 20)
$tabLic.Controls.Add($lblLicEmail)

$lblLicExp = New-Object System.Windows.Forms.Label
$lblLicExp.Location = New-Object System.Drawing.Point(12, 68)
$lblLicExp.Size     = New-Object System.Drawing.Size(840, 20)
$tabLic.Controls.Add($lblLicExp)

$lblLicFpHdr = New-Object System.Windows.Forms.Label
$lblLicFpHdr.Location = New-Object System.Drawing.Point(12, 96)
$lblLicFpHdr.Size     = New-Object System.Drawing.Size(200, 18)
$lblLicFpHdr.Text     = 'Machine fingerprint:'
$tabLic.Controls.Add($lblLicFpHdr)

$tbLicFp = New-Object System.Windows.Forms.TextBox
$tbLicFp.Location = New-Object System.Drawing.Point(12, 114)
$tbLicFp.Size     = New-Object System.Drawing.Size(700, 22)
$tbLicFp.ReadOnly = $true
$tbLicFp.Font     = New-Object System.Drawing.Font('Consolas', 9)
try {
    $fpDetail = Get-AGMachineFingerprint -ShowSource
    $tbLicFp.Text = $fpDetail.Fingerprint
    $lblLicFpHdr.Text = "Machine fingerprint (source: $($fpDetail.Source)$(if ($fpDetail.FromCache) { ', cached' })):"
} catch {
    $tbLicFp.Text = "ERROR: $($_.Exception.Message)"
}
$tabLic.Controls.Add($tbLicFp)

$btnLicCopyFp = New-Object System.Windows.Forms.Button
$btnLicCopyFp.Text = 'Copy'
$btnLicCopyFp.Location = New-Object System.Drawing.Point(720, 113)
$btnLicCopyFp.Size     = New-Object System.Drawing.Size(60, 24)
$btnLicCopyFp.Add_Click({ try { [System.Windows.Forms.Clipboard]::SetText($tbLicFp.Text) } catch { } })
$tabLic.Controls.Add($btnLicCopyFp)

$btnLicRequest = New-Object System.Windows.Forms.Button
$btnLicRequest.Text = 'Request License...'
$btnLicRequest.Location = New-Object System.Drawing.Point(12, 156)
$btnLicRequest.Size     = New-Object System.Drawing.Size(160, 32)
$btnLicRequest.BackColor = [System.Drawing.Color]::FromArgb(212, 168, 42)
$btnLicRequest.ForeColor = [System.Drawing.Color]::White
$tabLic.Controls.Add($btnLicRequest)

$btnLicActivate = New-Object System.Windows.Forms.Button
$btnLicActivate.Text = 'Activate License...'
$btnLicActivate.Location = New-Object System.Drawing.Point(180, 156)
$btnLicActivate.Size     = New-Object System.Drawing.Size(160, 32)
$tabLic.Controls.Add($btnLicActivate)

$btnLicRefresh = New-Object System.Windows.Forms.Button
$btnLicRefresh.Text = 'Refresh'
$btnLicRefresh.Location = New-Object System.Drawing.Point(348, 156)
$btnLicRefresh.Size     = New-Object System.Drawing.Size(80, 32)
$tabLic.Controls.Add($btnLicRefresh)

# ---- Telemetry diagnostics panel ----
# The user's license JWT authenticates EVERY usage event, with no client-
# side run counter. Each scan submits to /api/usage with a unique run_id,
# so the same key sends unlimited telemetry. This panel makes that
# guarantee visible: queue depth, last-result, manual flush button.
$grpTele = New-Object System.Windows.Forms.GroupBox
$grpTele.Text = ' Telemetry / Usage Submission '
$grpTele.Location = New-Object System.Drawing.Point(12, 200)
$grpTele.Size     = New-Object System.Drawing.Size(840, 160)
$grpTele.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$tabLic.Controls.Add($grpTele)

$lblTeleHelp = New-Object System.Windows.Forms.Label
$lblTeleHelp.Location = New-Object System.Drawing.Point(14, 22)
$lblTeleHelp.Size     = New-Object System.Drawing.Size(810, 36)
$lblTeleHelp.Font     = New-Object System.Drawing.Font('Segoe UI', 8)
$lblTeleHelp.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$lblTeleHelp.Text     = 'Your license JWT authenticates every telemetry event - the same key submits unlimited runs. Each scan ships a unique run_id to /api/usage. Failed submissions queue locally and retry automatically on the next scan; click Flush Queue Now to push them immediately.'
$grpTele.Controls.Add($lblTeleHelp)

$lblTeleStatus = New-Object System.Windows.Forms.Label
$lblTeleStatus.Location = New-Object System.Drawing.Point(14, 62)
$lblTeleStatus.Size     = New-Object System.Drawing.Size(540, 22)
$lblTeleStatus.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
$lblTeleStatus.Text     = 'Queue: (refreshing...)'
$grpTele.Controls.Add($lblTeleStatus)

$btnTeleFlush = New-Object System.Windows.Forms.Button
$btnTeleFlush.Text = 'Flush Queue Now'
$btnTeleFlush.Location = New-Object System.Drawing.Point(560, 60)
$btnTeleFlush.Size     = New-Object System.Drawing.Size(140, 26)
$grpTele.Controls.Add($btnTeleFlush)

$btnTeleOpenFolder = New-Object System.Windows.Forms.Button
$btnTeleOpenFolder.Text = 'Open Queue Folder'
$btnTeleOpenFolder.Location = New-Object System.Drawing.Point(706, 60)
$btnTeleOpenFolder.Size     = New-Object System.Drawing.Size(120, 26)
$grpTele.Controls.Add($btnTeleOpenFolder)

$lblTeleResult = New-Object System.Windows.Forms.Label
$lblTeleResult.Location = New-Object System.Drawing.Point(14, 92)
$lblTeleResult.Size     = New-Object System.Drawing.Size(810, 20)
$lblTeleResult.Font     = New-Object System.Drawing.Font('Segoe UI', 8)
$lblTeleResult.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$lblTeleResult.Text     = ''
$grpTele.Controls.Add($lblTeleResult)

$Script:UpdateTeleStatus = {
    try {
        $queueDir = Get-AGUsageQueueFolder
        $files = @()
        if (Test-Path $queueDir) { $files = @(Get-ChildItem -Path $queueDir -Filter '*.json' -File -ErrorAction SilentlyContinue) }
        $depth = $files.Count
        if ($depth -eq 0) {
            $lblTeleStatus.Text = "Queue: 0 pending events. Ready to submit on next scan."
            $lblTeleStatus.ForeColor = [System.Drawing.Color]::FromArgb(39, 174, 96)
        } else {
            $oldest = ($files | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime
            $lblTeleStatus.Text = "Queue: $depth pending event(s). Oldest queued: $($oldest.ToString('yyyy-MM-dd HH:mm'))."
            $lblTeleStatus.ForeColor = [System.Drawing.Color]::FromArgb(212, 168, 42)
        }
    } catch {
        $lblTeleStatus.Text = "Queue check failed: $($_.Exception.Message)"
        $lblTeleStatus.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
    }
}

$btnTeleFlush.Add_Click({
    $lblTeleResult.Text = 'Flushing queue...'
    $lblTeleResult.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $tabLic.Refresh()
    try {
        $r = Submit-AGUsageQueue
        $lblTeleResult.Text = "Drained $($r.Drained) event(s); $($r.Remaining) still queued."
        $lblTeleResult.ForeColor = if ($r.Remaining -eq 0) {
            [System.Drawing.Color]::FromArgb(39, 174, 96)
        } else {
            [System.Drawing.Color]::FromArgb(212, 168, 42)
        }
    } catch {
        $lblTeleResult.Text = "Flush failed: $($_.Exception.Message)"
        $lblTeleResult.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
    }
    & $Script:UpdateTeleStatus
})

$btnTeleOpenFolder.Add_Click({
    try {
        $queueDir = Get-AGUsageQueueFolder
        if (-not (Test-Path $queueDir)) { New-Item -ItemType Directory -Path $queueDir -Force | Out-Null }
        Start-Process explorer.exe $queueDir
    } catch {
        $lblTeleResult.Text = "Open folder failed: $($_.Exception.Message)"
        $lblTeleResult.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
    }
})

# Test-telemetry button: synthesizes a minimal AD-target payload, POSTs
# synchronously, and surfaces the exact HTTP response in a MessageBox so
# we can tell at a glance whether the portal accepts the payload shape
# or rejects it. Use this when an AD-only run completes but the run
# never appears on the dashboard - it isolates the network/portal layer
# from the runspace assembly logic.
$btnTeleTest = New-Object System.Windows.Forms.Button
$btnTeleTest.Text = 'Test Telemetry Now'
$btnTeleTest.Location = New-Object System.Drawing.Point(14, 124)
$btnTeleTest.Size     = New-Object System.Drawing.Size(180, 26)
$grpTele.Controls.Add($btnTeleTest)

$lblTeleTestResult = New-Object System.Windows.Forms.Label
$lblTeleTestResult.Location = New-Object System.Drawing.Point(204, 128)
$lblTeleTestResult.Size     = New-Object System.Drawing.Size(620, 20)
$lblTeleTestResult.Font     = New-Object System.Drawing.Font('Segoe UI', 8)
$lblTeleTestResult.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$lblTeleTestResult.Text     = '(click to POST a synthetic AD-only payload and see the portal response)'
$grpTele.Controls.Add($lblTeleTestResult)

$btnTeleTest.Add_Click({
    $btnTeleTest.Enabled = $false
    $lblTeleTestResult.Text = 'POSTing test payload to /api/usage...'
    $lblTeleTestResult.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $tabLic.Refresh()
    try {
        $fp = Get-AGMachineFingerprint
        $now = [int]([DateTimeOffset](Get-Date)).ToUnixTimeSeconds()
        $testPayload = @{
            run_id              = "test-$([guid]::NewGuid().ToString('N').Substring(0,16))"
            machine_fp          = $fp
            hostname            = $env:COMPUTERNAME
            tool_version        = "$Script:HealthCheckVersion-test"
            started_at          = $now - 1
            completed_at        = $now
            duration_seconds    = 1
            doc_author          = 'Test Telemetry button'
            customer_engagement = 'TELEMETRY-TEST'
            targets             = @(@{ type = 'AD'; fqdn = 'test.example.local' })
            plugin_count_total  = 1
            plugin_count_executed = 1
            findings_summary    = @{ P1=0; P2=0; P3=0; Info=1 }
            report_filename     = ''
            report_size_bytes   = 0
            status              = 'completed'
        }
        $r = Submit-AGUsageEvent -Payload $testPayload
        if ($r.Submitted) {
            $msg = "OK - the portal accepted a synthetic AD-target payload.`r`n`r`nThe AD-only telemetry path works at the network and validator layer. If real AD-only runs still are not appearing on the dashboard, the issue is upstream of submission (assembly, cleanup-tick firing, or runspace exit timing)."
            $lblTeleTestResult.Text = "OK: portal accepted AD-target payload."
            $lblTeleTestResult.ForeColor = [System.Drawing.Color]::FromArgb(39, 174, 96)
            [System.Windows.Forms.MessageBox]::Show($msg, 'Test Telemetry - Success', 'OK', 'Information') | Out-Null
        } elseif ($r.Queued) {
            $msg = "REJECTED - the portal returned an error and the payload was queued locally.`r`n`r`nServer error returned:`r`n$($r.Error)`r`n`r`nThe queued JSON is at:`r`n$(Get-AGUsageQueueFolder)`r`n`r`nMost common cause: the Zod validator on /api/usage does not include 'AD' in its 'targets[].type' enum. To fix, update the License Portal codebase + redeploy."
            $lblTeleTestResult.Text = "REJECTED + queued: $($r.Error)"
            $lblTeleTestResult.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
            [System.Windows.Forms.MessageBox]::Show($msg, 'Test Telemetry - Server Rejected', 'OK', 'Error') | Out-Null
        } else {
            $msg = "FAILED outright (no queue) - $($r.Error)"
            $lblTeleTestResult.Text = $msg
            $lblTeleTestResult.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
            [System.Windows.Forms.MessageBox]::Show($msg, 'Test Telemetry - Hard Failure', 'OK', 'Error') | Out-Null
        }
    } catch {
        $lblTeleTestResult.Text = "Threw: $($_.Exception.Message)"
        $lblTeleTestResult.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Test Telemetry - Exception', 'OK', 'Error') | Out-Null
    } finally {
        $btnTeleTest.Enabled = $true
        & $Script:UpdateTeleStatus
    }
})

# Refresh the status display from the on-disk license.
$Script:UpdateLicenseDisplay = {
    try {
        $r = Get-AGLicense
        if ($r.Valid) {
            $daysLeft = if ($r.ExpiresAt) { [math]::Round(($r.ExpiresAt - (Get-Date)).TotalHours / 24, 1) } else { 0 }
            $lblLicStatus.Text = "Status: ACTIVE - $daysLeft day(s) remaining (one license -> unlimited submissions)"
            $lblLicStatus.ForeColor = [System.Drawing.Color]::FromArgb(39, 174, 96)
            $lblLicEmail.Text = "Licensed to: $($r.Claims.sub)"
            $lblLicExp.Text   = "Expires: $($r.ExpiresAt) (UTC)"
        } else {
            $lblLicStatus.Text = "Status: NOT ACTIVE - $($r.Reason)"
            $lblLicStatus.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
            $lblLicEmail.Text = ''
            $lblLicExp.Text   = 'Click Request License to start. The license token will be emailed to the address you submit.'
        }
    } catch {
        $lblLicStatus.Text = "Status: License module error - $($_.Exception.Message)"
        $lblLicStatus.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
    }
    try { & $Script:UpdateTeleStatus } catch { }
}
& $Script:UpdateLicenseDisplay

$btnLicRefresh.Add_Click({ & $Script:UpdateLicenseDisplay })

# ---- Request License: small dialog collects email + engagement + author + ----
# ---- company, opens the system browser at the prefilled URL.            ----
$btnLicRequest.Add_Click({
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Request License'
    $dlg.Size = New-Object System.Drawing.Size(520, 360)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'Sizable'
    $dlg.MinimumSize = New-Object System.Drawing.Size(420, 300)
    $dlg.AutoScroll = $true

    $lblHdr = New-Object System.Windows.Forms.Label
    $lblHdr.Text = 'Fill in your details. Your default browser will open at License.AuthorityGate.com with everything pre-filled. Click Submit on the page; the license token is emailed to you. Paste the token into the Activate License dialog to complete activation.'
    $lblHdr.Location = New-Object System.Drawing.Point(12, 8); $lblHdr.Size = New-Object System.Drawing.Size(490, 60)
    $dlg.Controls.Add($lblHdr)

    function _addLF { param($y, $label, $default = '')
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $label
        $l.Location = New-Object System.Drawing.Point(12, $y); $l.Size = New-Object System.Drawing.Size(120, 20)
        $dlg.Controls.Add($l)
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point(140, $y); $tb.Size = New-Object System.Drawing.Size(360, 22)
        $tb.Text = $default
        $dlg.Controls.Add($tb)
        $tb
    }
    $tbE = _addLF 80 'Email *'
    $tbC = _addLF 110 'Company'
    $tbX = _addLF 140 'Engagement'
    $tbA = _addLF 170 'Doc author'
    $tbH = _addLF 200 'Hostname' $env:COMPUTERNAME

    $btnGo = New-Object System.Windows.Forms.Button
    $btnGo.Text = 'Open Browser to Submit'
    $btnGo.Location = New-Object System.Drawing.Point(140, 240); $btnGo.Size = New-Object System.Drawing.Size(200, 32)
    $btnGo.BackColor = [System.Drawing.Color]::FromArgb(212, 168, 42); $btnGo.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnGo)
    $btnGo.Add_Click({
        if (-not $tbE.Text.Trim()) {
            [System.Windows.Forms.MessageBox]::Show('Email is required.', 'License', 'OK', 'Warning') | Out-Null
            return
        }
        try {
            $url = Get-AGRequestDeepLink -Email $tbE.Text.Trim() -Engagement $tbX.Text.Trim() -DocAuthor $tbA.Text.Trim() -Company $tbC.Text.Trim() -Hostname $tbH.Text.Trim()
            Start-Process $url
            [System.Windows.Forms.MessageBox]::Show("Browser opening at License.AuthorityGate.com.`r`n`r`nReview the prefilled values and click Submit. The license token will be emailed to: $($tbE.Text.Trim())`r`n`r`nWhen you receive it, click Activate License... and paste the token.", 'License Request', 'OK', 'Information') | Out-Null
            $dlg.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to open browser: $($_.Exception.Message)", 'License', 'OK', 'Error') | Out-Null
        }
    })

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Location = New-Object System.Drawing.Point(346, 240); $btnCancel.Size = New-Object System.Drawing.Size(100, 32)
    $btnCancel.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnCancel)

    [void]$dlg.ShowDialog($form)
})

# ---- Activate License: paste-and-validate dialog ----------------------------
$btnLicActivate.Add_Click({
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Activate License'
    $dlg.Size = New-Object System.Drawing.Size(700, 380)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'Sizable'
    $dlg.MinimumSize = New-Object System.Drawing.Size(540, 320)
    $dlg.AutoScroll = $true

    $lblHdr = New-Object System.Windows.Forms.Label
    $lblHdr.Text = 'Paste the license token from the email you received from architect@authoritygate.com (subject: "Your HealthCheckPS1 License"). Whitespace and line breaks are fine - they will be stripped. Click Activate to validate and store.'
    $lblHdr.Location = New-Object System.Drawing.Point(12, 8); $lblHdr.Size = New-Object System.Drawing.Size(670, 50)
    $dlg.Controls.Add($lblHdr)

    $tbToken = New-Object System.Windows.Forms.TextBox
    $tbToken.Location = New-Object System.Drawing.Point(12, 64); $tbToken.Size = New-Object System.Drawing.Size(660, 200)
    $tbToken.Multiline = $true; $tbToken.ScrollBars = 'Vertical'
    $tbToken.Font = New-Object System.Drawing.Font('Consolas', 8)
    $dlg.Controls.Add($tbToken)

    $btnAct = New-Object System.Windows.Forms.Button
    $btnAct.Text = 'Activate'
    $btnAct.Location = New-Object System.Drawing.Point(12, 280); $btnAct.Size = New-Object System.Drawing.Size(120, 32)
    $btnAct.BackColor = [System.Drawing.Color]::FromArgb(39, 174, 96); $btnAct.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnAct)

    $btnX = New-Object System.Windows.Forms.Button
    $btnX.Text = 'Cancel'
    $btnX.Location = New-Object System.Drawing.Point(140, 280); $btnX.Size = New-Object System.Drawing.Size(100, 32)
    $btnX.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnX)

    $btnAct.Add_Click({
        $clean = ($tbToken.Text -replace '\s+','')
        if (-not $clean) {
            [System.Windows.Forms.MessageBox]::Show('Paste the license token first.', 'Activate', 'OK', 'Warning') | Out-Null
            return
        }
        try {
            $r = Save-AGLicense -Token $clean
            [System.Windows.Forms.MessageBox]::Show("License activated.`r`n`r`nLicensed to: $($r.Claims.sub)`r`nExpires: $($r.ExpiresAt) (UTC)", 'License Activated', 'OK', 'Information') | Out-Null
            & $Script:UpdateLicenseDisplay
            $dlg.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Activation failed: $($_.Exception.Message)", 'Activate', 'OK', 'Error') | Out-Null
        }
    })

    [void]$dlg.ShowDialog($form)
})

$tabHV  = New-Object System.Windows.Forms.TabPage; $tabHV.Text  = 'Horizon';     $tabs.TabPages.Add($tabHV)
$cHV  = New-PanelControls $tabHV  $true
$cHV.Use.Text    = 'Connect to Horizon Connection Server (one FQDN per pod, comma- or semicolon-separated for multi-pod)'
$cHV.Use.Checked = $state.UseHorizon
$cHV.Server.Text = $state.HVServer
$cHV.User.Text   = $state.HVUser
$cHV.Domain.Text = $state.HVDomain
$cHV.SkipCert.Checked = $state.HVSkipCert

# Hv.Helper (Omnissa PowerCLI Horizon snap-in) presence badge. The SOAP/Web
# Services API the snap-in wraps is the only reliable source for full pod
# inventory + per-pool entitlements on Horizon 8.6 (REST has gaps). Status
# is informational - REST still works without it; just with reduced data.
$_hvHelper = Get-Module -ListAvailable -Name VMware.Hv.Helper -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending | Select-Object -First 1
$cHV.LblHvHelper = New-Object System.Windows.Forms.Label
if ($_hvHelper) {
    $cHV.LblHvHelper.Text = "VMware.Hv.Helper $($_hvHelper.Version) installed (SOAP fallback active for Horizon 8.6 REST gaps)."
    $cHV.LblHvHelper.ForeColor = [System.Drawing.Color]::FromArgb(39, 174, 96)
} else {
    $cHV.LblHvHelper.Text = 'VMware.Hv.Helper NOT installed - REST-only mode. On Horizon 8.6, /v1/monitor/connection-servers + entitlements may return stub data. Run Install-Prerequisites.cmd.'
    $cHV.LblHvHelper.ForeColor = [System.Drawing.Color]::FromArgb(192, 130, 0)
}
$cHV.LblHvHelper.Location = New-Object System.Drawing.Point(14, 200)
$cHV.LblHvHelper.Size     = New-Object System.Drawing.Size(720, 32)
$cHV.LblHvHelper.Font     = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$tabHV.Controls.Add($cHV.LblHvHelper)

# ADAM (AD-LDS) credential picker. Read-only LDAPS pull from each CS's local
# ADAM instance - authoritative source for pool entitlements when the REST
# /v1/entitlements + /v2/entitlements endpoints 404 (Horizon 8.6 default).
# Field is OPERATOR-CONFIGURABLE and persists only via the credential
# profile system - no real customer account is ever stored as a default.
$cHV.LblAdam = New-Object System.Windows.Forms.Label
$cHV.LblAdam.Text = 'ADAM/AD-LDS read-only credential (optional - enables authoritative pool entitlement pull when REST entitlement endpoints 404):'
$cHV.LblAdam.Location = New-Object System.Drawing.Point(14, 238)
$cHV.LblAdam.Size = New-Object System.Drawing.Size(720, 16)
$cHV.LblAdam.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$cHV.LblAdam.ForeColor = [System.Drawing.Color]::FromArgb(96, 96, 96)
$tabHV.Controls.Add($cHV.LblAdam)

$cHV.BtnAdamCred = New-Object System.Windows.Forms.Button
$cHV.BtnAdamCred.Text = 'Set ADAM credential...'
$cHV.BtnAdamCred.Location = New-Object System.Drawing.Point(14, 258)
$cHV.BtnAdamCred.Size = New-Object System.Drawing.Size(180, 24)
$cHV.BtnAdamCred.FlatStyle = 'Flat'
$cHV.BtnAdamCred.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$tabHV.Controls.Add($cHV.BtnAdamCred)

$cHV.LblAdamStatus = New-Object System.Windows.Forms.Label
$cHV.LblAdamStatus.Text = '(no ADAM credential set; entitlement pull falls back to REST + SOAP)'
$cHV.LblAdamStatus.Location = New-Object System.Drawing.Point(204, 262)
$cHV.LblAdamStatus.Size = New-Object System.Drawing.Size(540, 18)
$cHV.LblAdamStatus.ForeColor = [System.Drawing.Color]::FromArgb(96, 96, 96)
$cHV.LblAdamStatus.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Italic)
$tabHV.Controls.Add($cHV.LblAdamStatus)

# Generic placeholder for tooltips/example - never a real customer account.
$cHV.AdamTooltip = New-Object System.Windows.Forms.ToolTip
$cHV.AdamTooltip.SetToolTip($cHV.BtnAdamCred,
    "Pick a credential profile authorized for read-only LDAPS bind on the Connection Server's ADAM instance (typically port 636, DN base OU=Applications,DC=vdi,DC=vmware,DC=int). Example service account: svc-healthcheck@example.local. The credential is decrypted into memory only - never written back to disk by this tool.")

# Click handler builds the same dictionary-based menu the Profile... button
# uses. Tag-based ref passing avoids the closure-capture bugs that bit
# .GetNewClosure() in past releases. Selecting a profile populates the
# $Global:HVAdamProfileName session variable; the runspace decrypts and
# uses it when running ADAM-backed plugins.
$cHV.BtnAdamCred.Add_Click({
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $profiles = @(Get-AGCredentialProfile | Sort-Object Name)
    if ($profiles.Count -eq 0) {
        $mi = $menu.Items.Add('(no profiles - click Manage Credentials... to add one)')
        $mi.Enabled = $false
    } else {
        foreach ($p in $profiles) {
            $mi = $menu.Items.Add("$($p.Name)  -  $($p.UserName)  [$($p.Type)]")
            $mi.Tag = @{ Profile = $p; Status = $cHV.LblAdamStatus }
            $mi.Add_Click({
                param($s,$e)
                $tag = $s.Tag
                $sel = $tag.Profile
                $Global:HVAdamProfileName = $sel.Name
                $tag.Status.Text = "ADAM cred: $($sel.Name) (user: $($sel.UserName)) - read-only, in-memory only"
                $tag.Status.ForeColor = [System.Drawing.Color]::FromArgb(39, 174, 96)
            })
        }
        $menu.Items.Add('-') | Out-Null
    }
    $miClear = $menu.Items.Add('Clear ADAM credential')
    $miClear.Tag = $cHV.LblAdamStatus
    $miClear.Add_Click({
        param($s,$e)
        $Global:HVAdamProfileName = $null
        $s.Tag.Text = '(no ADAM credential set; entitlement pull falls back to REST + SOAP)'
        $s.Tag.ForeColor = [System.Drawing.Color]::FromArgb(96, 96, 96)
    })
    $miMgr = $menu.Items.Add('Manage Credentials...')
    $miMgr.Add_Click({ Show-CredentialProfileDialog })
    $menu.Show($cHV.BtnAdamCred, 0, $cHV.BtnAdamCred.Height)
})

$tabVC  = New-Object System.Windows.Forms.TabPage; $tabVC.Text  = 'vCenter';     $tabs.TabPages.Add($tabVC)
$cVC  = New-PanelControls $tabVC  $false
$cVC.Use.Text    = 'Connect to vCenter Server (one FQDN, comma- or semicolon-separated for multi-vCenter)'
$cVC.Use.Checked = $state.UseVCenter
$cVC.Server.Text = $state.VCServer
$cVC.User.Text   = $state.VCUser
$cVC.SkipCert.Checked = $state.VCSkipCert
# Hint: multi-vCenter via comma/semicolon separator (placed below the Test
# button row at y=210 so it does not collide with SkipCert at y=138).
$lblVcMulti = New-Object System.Windows.Forms.Label
$lblVcMulti.Text = 'Multi-vCenter: separate FQDNs with commas (e.g. vc1.lab,vc2.lab) - same credential is used for each.'
$lblVcMulti.Location = New-Object System.Drawing.Point(14, 210)
$lblVcMulti.Size     = New-Object System.Drawing.Size(720, 18)
$lblVcMulti.ForeColor = [System.Drawing.Color]::FromArgb(96, 96, 96)
$lblVcMulti.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Italic)
$tabVC.Controls.Add($lblVcMulti)

$tabAV  = New-Object System.Windows.Forms.TabPage; $tabAV.Text  = 'App Volumes'; $tabs.TabPages.Add($tabAV)
$cAV  = New-PanelControls $tabAV  $false
$cAV.Use.Text    = 'Connect to App Volumes Manager'
$cAV.Use.Checked = $state.UseAV
$cAV.Server.Text = $state.AVServer
$cAV.User.Text   = $state.AVUser
$cAV.SkipCert.Checked = $state.AVSkipCert

# AppVolumes Packaging VMs - moved here from the Specialized Scope dialog.
# When set, the AppVolumes packaging-machine deep-scan plugin probes each
# named VM via WinRM (Tier 2). One VM name per line.
$tabAV.Controls.Add((New-Label 'Packaging VM names (one per line - optional, deep-scan only):' 14 165 600))
$cAV.PackagingVms = New-Object System.Windows.Forms.TextBox
$cAV.PackagingVms.Location = New-Object System.Drawing.Point(14, 185)
$cAV.PackagingVms.Size     = New-Object System.Drawing.Size(600, 60)
$cAV.PackagingVms.Multiline = $true
$cAV.PackagingVms.ScrollBars = 'Vertical'
$cAV.PackagingVms.Text = $state.AVPackagingVms
$tabAV.Controls.Add($cAV.PackagingVms)

$tabNTNX = New-Object System.Windows.Forms.TabPage; $tabNTNX.Text = 'Nutanix'; $tabs.TabPages.Add($tabNTNX)
$cNTNX = New-PanelControls $tabNTNX $false
$cNTNX.Use.Text    = 'Connect to Nutanix Prism Central / Element (one FQDN, comma- or semicolon-separated for multi-target)'
$cNTNX.Use.Checked = $state.UseNTNX
$cNTNX.Server.Text = $state.NTNXServer
$cNTNX.User.Text   = $state.NTNXUser
$cNTNX.SkipCert.Checked = $state.NTNXSkipCert
$tabNTNX.Controls.Add((New-Label 'Prism port' 480 50 60))
$cNTNX.Port = New-TextBox 540 48 60 ($state.NTNXPort.ToString())
$tabNTNX.Controls.Add($cNTNX.Port)

# Generate Access Request: opens a dialog with a pre-filled forwardable
# email asking the customer's Nutanix admin to create a read-only service
# account using the bundled docs/Nutanix-ReadOnly-Role.json. Three actions:
# Copy to clipboard, Open in Outlook (COM), Save as .txt for manual paste.
$cNTNX.RequestAccess = New-Object System.Windows.Forms.Button
$cNTNX.RequestAccess.Text = 'Generate Access Request Email...'
$cNTNX.RequestAccess.Location = New-Object System.Drawing.Point(14, 250)
$cNTNX.RequestAccess.Size     = New-Object System.Drawing.Size(220, 30)
$cNTNX.RequestAccess.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$cNTNX.RequestAccess.FlatStyle = 'Flat'
$cNTNX.RequestAccess.Add_Click({
    Show-NutanixAccessRequestDialog -RootPath $root -PrismFqdn $cNTNX.Server.Text -ServiceAccountUser $cNTNX.User.Text
})
$tabNTNX.Controls.Add($cNTNX.RequestAccess)
$lblHelp = New-Object System.Windows.Forms.Label
$lblHelp.Text = "If your environment doesn't have a read-only Nutanix service account, click above to generate a pre-filled request email for your Nutanix admin (includes the read-only role JSON they need to import)."
$lblHelp.Location = New-Object System.Drawing.Point(14, 285)
$lblHelp.Size     = New-Object System.Drawing.Size(620, 50)
$lblHelp.ForeColor = [System.Drawing.Color]::FromArgb(96, 96, 96)
$lblHelp.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Italic)
$tabNTNX.Controls.Add($lblHelp)

# Workspace ONE Access (vIDM) tab - OAuth client_credentials grant.
# User field = OAuth Client ID; Password field = Shared Secret.
$tabVIDM = New-Object System.Windows.Forms.TabPage; $tabVIDM.Text = 'vIDM'; $tabs.TabPages.Add($tabVIDM)
$cVIDM = New-PanelControls $tabVIDM $false
$cVIDM.Use.Text    = 'Connect to Workspace ONE Access (vIDM) - OAuth client credentials'
$cVIDM.Use.Checked = $state.UseVIDM
$cVIDM.Server.Text = $state.VIDMServer
$cVIDM.User.Text   = $state.VIDMClientId
$cVIDM.SkipCert.Checked = $state.VIDMSkipCert
$tabVIDM.Controls.Add((New-Label 'OAuth Client ID -> Username field. Shared Secret -> Password field.' 14 145 720))
$tabVIDM.Controls.Add((New-Label 'Tenant path' 14 175 100))
$cVIDM.TenantPath = New-TextBox 140 173 240 $state.VIDMTenantPath
$tabVIDM.Controls.Add($cVIDM.TenantPath)

# Workspace ONE UEM (AirWatch) tab - Basic auth + aw-tenant-code header.
$tabUEM = New-Object System.Windows.Forms.TabPage; $tabUEM.Text = 'WS1 UEM'; $tabs.TabPages.Add($tabUEM)
$cUEM = New-PanelControls $tabUEM $false
$cUEM.Use.Text    = 'Connect to Workspace ONE UEM (AirWatch) - Basic auth + tenant API key'
$cUEM.Use.Checked = $state.UseUEM
$cUEM.Server.Text = $state.UEMServer
$cUEM.User.Text   = $state.UEMUser
$cUEM.SkipCert.Checked = $state.UEMSkipCert
$tabUEM.Controls.Add((New-Label 'Tenant API key (aw-tenant-code header):' 14 145 360))
$cUEM.ApiKey = New-Object System.Windows.Forms.TextBox
$cUEM.ApiKey.Location = New-Object System.Drawing.Point(14, 165)
$cUEM.ApiKey.Size     = New-Object System.Drawing.Size(540, 22)
$cUEM.ApiKey.UseSystemPasswordChar = $true
$tabUEM.Controls.Add($cUEM.ApiKey)
$lblUEMHelp = New-Object System.Windows.Forms.Label
$lblUEMHelp.Text = 'Find the tenant API key in UEM Console -> All Settings -> System -> Advanced -> API -> REST API.'
$lblUEMHelp.Location = New-Object System.Drawing.Point(14, 195)
$lblUEMHelp.Size     = New-Object System.Drawing.Size(620, 22)
$lblUEMHelp.ForeColor = [System.Drawing.Color]::FromArgb(96, 96, 96)
$lblUEMHelp.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Italic)
$tabUEM.Controls.Add($lblUEMHelp)

# ---- Active Directory tab -----------------------------------------------
# AD plugins traverse one or more forests/domains. Each row in the grid
# carries a Forest FQDN + an optional credential-profile name. Empty profile
# = run AD cmdlets under the current Windows user. Plugins are invoked
# once per row in the runner, so a single health-check can validate
# replication, sites, FSMO etc. across multiple domains/trusts.
$tabAD = New-Object System.Windows.Forms.TabPage; $tabAD.Text = 'AD'; $tabs.TabPages.Add($tabAD)
$cAD = @{}
$cAD.Use = New-Object System.Windows.Forms.CheckBox
$cAD.Use.Text     = 'Probe configured AD forests / domains (uses RSAT ActiveDirectory module)'
$cAD.Use.Location = New-Object System.Drawing.Point(20, 18); $cAD.Use.Size = New-Object System.Drawing.Size(620, 22)
$cAD.Use.Checked  = $state.UseAD
$tabAD.Controls.Add($cAD.Use)

$lblADHdr = New-Object System.Windows.Forms.Label
$lblADHdr.Text = "DC/Server is the FQDN of the DC or DNS server the runner can reach (e.g. 'dc01.example.local'). Forest is the forest identity (e.g. 'example.local') and can be left blank to auto-discover. Credential is optional - blank = current Windows user."
$lblADHdr.Location = New-Object System.Drawing.Point(20, 44); $lblADHdr.Size = New-Object System.Drawing.Size(620, 32)
$lblADHdr.ForeColor = [System.Drawing.Color]::FromArgb(96, 96, 96)
$lblADHdr.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Italic)
$tabAD.Controls.Add($lblADHdr)

# Buttons row first (above grid) so they're always visible regardless of
# tab page height. Grid grows downward with anchor; buttons stay anchored
# to the top.
$cAD.BtnAdd = New-Object System.Windows.Forms.Button
$cAD.BtnAdd.Text = 'Add forest...'
$cAD.BtnAdd.Location = New-Object System.Drawing.Point(20, 82); $cAD.BtnAdd.Size = New-Object System.Drawing.Size(120, 26)
$cAD.BtnAdd.FlatStyle = 'Flat'
$tabAD.Controls.Add($cAD.BtnAdd)

$cAD.BtnCred = New-Object System.Windows.Forms.Button
$cAD.BtnCred.Text = 'Set credential...'
$cAD.BtnCred.Location = New-Object System.Drawing.Point(150, 82); $cAD.BtnCred.Size = New-Object System.Drawing.Size(140, 26)
$cAD.BtnCred.FlatStyle = 'Flat'
$tabAD.Controls.Add($cAD.BtnCred)

$cAD.BtnRemove = New-Object System.Windows.Forms.Button
$cAD.BtnRemove.Text = 'Remove selected'
$cAD.BtnRemove.Location = New-Object System.Drawing.Point(300, 82); $cAD.BtnRemove.Size = New-Object System.Drawing.Size(130, 26)
$cAD.BtnRemove.FlatStyle = 'Flat'
$tabAD.Controls.Add($cAD.BtnRemove)

$cAD.BtnTest = New-Object System.Windows.Forms.Button
$cAD.BtnTest.Text = 'Test all'
$cAD.BtnTest.Location = New-Object System.Drawing.Point(440, 82); $cAD.BtnTest.Size = New-Object System.Drawing.Size(110, 26)
$cAD.BtnTest.FlatStyle = 'Flat'
$tabAD.Controls.Add($cAD.BtnTest)

$cAD.Grid = New-Object System.Windows.Forms.DataGridView
$cAD.Grid.Location = New-Object System.Drawing.Point(20, 116)
$cAD.Grid.Size     = New-Object System.Drawing.Size(620, 130)
$cAD.Grid.AllowUserToAddRows    = $false
$cAD.Grid.AllowUserToDeleteRows = $false
$cAD.Grid.MultiSelect           = $false
$cAD.Grid.SelectionMode         = 'FullRowSelect'
$cAD.Grid.RowHeadersVisible     = $false
$cAD.Grid.AutoSizeColumnsMode   = 'Fill'
$cAD.Grid.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$null = $cAD.Grid.Columns.Add('colDC','DC / DNS Server FQDN')
$null = $cAD.Grid.Columns.Add('colForest','Forest FQDN (optional)')
$null = $cAD.Grid.Columns.Add('colCred','Credential Profile')
$null = $cAD.Grid.Columns.Add('colStatus','Status')
$cAD.Grid.Columns['colStatus'].ReadOnly = $true
$tabAD.Controls.Add($cAD.Grid)

# Dynamic status line: lists every configured DC/Forest so the operator
# can see at a glance what will be probed - matches the user request to
# "have the AD server in the text".
$cAD.LblStatus = New-Object System.Windows.Forms.Label
$cAD.LblStatus.Location = New-Object System.Drawing.Point(20, 252)
$cAD.LblStatus.Size     = New-Object System.Drawing.Size(620, 32)
$cAD.LblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 100, 0)
$cAD.LblStatus.Font     = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$cAD.LblStatus.Text = '(no forests configured)'
$cAD.LblStatus.AutoEllipsis = $true
$tabAD.Controls.Add($cAD.LblStatus)

# Status updater - call after any row mutation
function Global:Update-ADStatusLabel {
    if (-not $cAD -or -not $cAD.Grid) { return }
    $entries = @()
    foreach ($r in $cAD.Grid.Rows) {
        $dc = [string]$r.Cells['colDC'].Value
        if (-not $dc) { continue }
        $f = [string]$r.Cells['colForest'].Value
        if ($f) { $entries += "$dc (forest=$f)" } else { $entries += $dc }
    }
    if ($entries.Count -eq 0) {
        $cAD.LblStatus.Text = '(no forests configured)'
        $cAD.LblStatus.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
    } else {
        $cAD.LblStatus.Text = "Configured ($($entries.Count)): $($entries -join '  |  ')"
        $cAD.LblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 100, 0)
    }
}
$cAD.Grid.Add_RowsAdded({ Update-ADStatusLabel })
$cAD.Grid.Add_RowsRemoved({ Update-ADStatusLabel })
$cAD.Grid.Add_CellEndEdit({ Update-ADStatusLabel })

# Pre-populate from saved state. Tolerates rows written by older builds that
# only had a single Forest field - in that case Server defaults to the same.
foreach ($e in @($state.ADForests)) {
    if (-not $e) { continue }
    $dc = ''
    $f  = ''
    $cp = ''
    if ($e.PSObject) {
        if ($e.PSObject.Properties['Server'])      { $dc = [string]$e.Server }
        if ($e.PSObject.Properties['Forest'])      { $f  = [string]$e.Forest }
        if ($e.PSObject.Properties['CredProfile']) { $cp = [string]$e.CredProfile }
    }
    if (-not $dc -and $f) { $dc = $f }   # legacy single-field row
    if (-not $dc) { continue }
    [void]$cAD.Grid.Rows.Add($dc, $f, $cp, '')
}

# Wire click handlers to the buttons created above (above the grid).

$cAD.BtnAdd.Add_Click({
    $dc = Read-NameDialog -Title 'Add DC / DNS server' -Prompt "Reachable DC or DNS server FQDN (e.g. 'dc01.example.local'):" -DefaultValue ''
    if (-not $dc) { return }
    $dc = $dc.Trim()
    # Validate FQDN form - a bare short hostname like 'DOGWOOD01' won't be
    # DNS-resolvable and AD Web Services connections will fail. We still
    # let the user proceed but warn them clearly.
    if ($dc -notmatch '\.') {
        $ans = [System.Windows.Forms.MessageBox]::Show(
            "'$dc' looks like a short hostname (no domain suffix). AD Web Services connections need a fully-qualified name like '$dc.example.local' or just 'example.local'. Add anyway?",
            'Possible incomplete FQDN', 'YesNo', 'Warning')
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }
    $f = Read-NameDialog -Title 'Forest FQDN (optional)' -Prompt "Forest FQDN (e.g. 'example.local'). Leave blank to auto-discover from the DC above:" -DefaultValue ''
    [void]$cAD.Grid.Rows.Add($dc, ($(if ($f) { $f.Trim() } else { '' })), '', '')
    Update-ADStatusLabel
})

$cAD.BtnCred.Tag = @{ Grid = $cAD.Grid }
$cAD.BtnCred.Add_Click({
    param($s,$e)
    $g = $s.Tag.Grid
    if (-not $g -or $g.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Select a row first.', 'Set credential', 'OK', 'Information') | Out-Null
        return
    }
    $row = $g.SelectedRows[0]
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $profiles = @(Get-AGCredentialProfile | Where-Object { $_.Type -in 'Domain','Other' } | Sort-Object Name)
    foreach ($p in $profiles) {
        $mi = $menu.Items.Add("Use profile: $($p.Name)  -  $($p.UserName)")
        $mi.Tag = @{ Profile = $p.Name; Row = $row }
        $mi.Add_Click({
            param($mis,$me)
            $t = $mis.Tag
            if ($t -and $t.Row) { $t.Row.Cells['colCred'].Value = $t.Profile }
        })
    }
    if ($profiles.Count -gt 0) { $menu.Items.Add('-') | Out-Null }
    $miClear = $menu.Items.Add('Clear (use current Windows credentials)')
    $miClear.Tag = @{ Row = $row }
    $miClear.Add_Click({ param($mis,$me) if ($mis.Tag -and $mis.Tag.Row) { $mis.Tag.Row.Cells['colCred'].Value = '' } })
    $miMgr = $menu.Items.Add('Manage Credentials...')
    $miMgr.Add_Click({ Show-CredentialProfileDialog })
    $menu.Show($s, 0, $s.Height)
})

$cAD.BtnRemove.Tag = @{ Grid = $cAD.Grid }
$cAD.BtnRemove.Add_Click({
    param($s,$e)
    $g = $s.Tag.Grid
    if (-not $g -or $g.SelectedRows.Count -eq 0) { return }
    $g.Rows.Remove($g.SelectedRows[0])
    Update-ADStatusLabel
})

$cAD.BtnTest.Tag = @{ Grid = $cAD.Grid }
$cAD.BtnTest.Add_Click({
    param($s,$e)
    $g = $s.Tag.Grid
    if (-not $g) { return }
    if ($g.Rows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No forests configured yet. Click 'Add forest...' first to add a DC/DNS server FQDN.", 'Test forests', 'OK', 'Information') | Out-Null
        return
    }
    if (-not (Get-Module -ListAvailable ActiveDirectory)) {
        [System.Windows.Forms.MessageBox]::Show("RSAT ActiveDirectory module is not installed on this runner. Click 'Install RSAT now...' below the grid, then close + reopen the GUI before testing.", 'Test forests', 'OK', 'Warning') | Out-Null
        return
    }
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue | Out-Null
    $okCount = 0; $failCount = 0
    foreach ($row in $g.Rows) {
        $dc = [string]$row.Cells['colDC'].Value
        $forest = [string]$row.Cells['colForest'].Value
        $cp = [string]$row.Cells['colCred'].Value
        if (-not $dc) { $row.Cells['colStatus'].Value = '(no DC FQDN)'; $failCount++; continue }
        $row.Cells['colStatus'].Value = 'testing...'
        [System.Windows.Forms.Application]::DoEvents()
        $adArgs = @{ Server = $dc; ErrorAction = 'Stop' }
        if ($cp) {
            try { $adArgs.Credential = Get-AGCredentialAsPSCredential -Name $cp } catch {
                $row.Cells['colStatus'].Value = "cred decrypt failed: $($_.Exception.Message)"
                $failCount++
                continue
            }
        }
        try {
            $d = Get-ADDomain @adArgs
            $statusMsg = "OK (DNSRoot=$($d.DNSRoot), Forest=$($d.Forest))"
            if (-not $forest) {
                $row.Cells['colForest'].Value = [string]$d.Forest
            } elseif ($forest -ne $d.Forest) {
                $statusMsg += " - WARNING: configured Forest '$forest' != DC's actual Forest '$($d.Forest)'"
            }
            $row.Cells['colStatus'].Value = $statusMsg
            $okCount++
        } catch {
            $row.Cells['colStatus'].Value = "FAIL: $($_.Exception.Message)"
            $failCount++
        }
    }
    Update-ADStatusLabel
    [System.Windows.Forms.MessageBox]::Show("Tested $($g.Rows.Count) forest(s): $okCount OK, $failCount failed. See the Status column for per-row detail.", 'Test forests', 'OK', 'Information') | Out-Null
})

# RSAT presence + install button (moved here from the Specialized Scope
# dialog - belongs with the AD configuration that needs it). Checks ALL
# four modules the B3/B4 plugin set needs (AD + GroupPolicy + DnsServer +
# DhcpServer) so the operator can see which are missing instead of seeing
# an 'all good' for AD while DNS/DHCP/GPO plugins silently skip.
$_rsatNeeded = @(
    @{ Module='ActiveDirectory'; Label='AD' }
    @{ Module='GroupPolicy';     Label='GroupPolicy' }
    @{ Module='DnsServer';       Label='DNS' }
    @{ Module='DhcpServer';      Label='DHCP' }
)
$_rsatPresent = @($_rsatNeeded | Where-Object { Get-Module -ListAvailable $_.Module -ErrorAction SilentlyContinue })
$_rsatMissing = @($_rsatNeeded | Where-Object { -not (Get-Module -ListAvailable $_.Module -ErrorAction SilentlyContinue) })
$rsatPresentAD = ($_rsatMissing.Count -eq 0)
$cAD.LblRsat = New-Object System.Windows.Forms.Label
if ($rsatPresentAD) {
    $cAD.LblRsat.Text = "RSAT modules: ALL INSTALLED ($($_rsatPresent.Label -join ', '))"
    $cAD.LblRsat.ForeColor = [System.Drawing.Color]::FromArgb(39, 174, 96)
} elseif ($_rsatPresent.Count -gt 0) {
    $cAD.LblRsat.Text = "RSAT: $($_rsatPresent.Count)/$($_rsatNeeded.Count) installed. Missing: $($_rsatMissing.Label -join ', ')"
    $cAD.LblRsat.ForeColor = [System.Drawing.Color]::FromArgb(192, 130, 0)
} else {
    $cAD.LblRsat.Text = "RSAT modules NOT installed: $($_rsatMissing.Label -join ', '). AD/DNS/DHCP/GPO plugins will skip."
    $cAD.LblRsat.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
}
$cAD.LblRsat.Location = New-Object System.Drawing.Point(20, 290); $cAD.LblRsat.Size = New-Object System.Drawing.Size(440, 18)
$cAD.LblRsat.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$tabAD.Controls.Add($cAD.LblRsat)

$cAD.BtnRsat = New-Object System.Windows.Forms.Button
$cAD.BtnRsat.Text = if ($rsatPresentAD) { 'RSAT installed' } else { 'Install RSAT now...' }
$cAD.BtnRsat.Location = New-Object System.Drawing.Point(470, 286); $cAD.BtnRsat.Size = New-Object System.Drawing.Size(170, 24)
$cAD.BtnRsat.Enabled = (-not $rsatPresentAD)
$cAD.BtnRsat.Add_Click({
    $rsatScript = Join-Path $PSScriptRoot 'Tools\Install-RSAT.ps1'
    if (-not (Test-Path $rsatScript)) {
        [System.Windows.Forms.MessageBox]::Show("Install-RSAT.ps1 not found at $rsatScript.", 'RSAT install', 'OK', 'Error') | Out-Null
        return
    }
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$rsatScript) -WindowStyle Normal
    [System.Windows.Forms.MessageBox]::Show("RSAT install launched in elevated PowerShell. Wait for it to complete (~1-2 min), then close + reopen this GUI to detect the new module.", 'RSAT install', 'OK', 'Information') | Out-Null
})
$tabAD.Controls.Add($cAD.BtnRsat)

# Initial status update for any rows pre-loaded from state.json
Update-ADStatusLabel

$tabUAG = New-Object System.Windows.Forms.TabPage; $tabUAG.Text = 'UAG';         $tabs.TabPages.Add($tabUAG)
$cUAG = New-PanelControls $tabUAG $false
$cUAG.Use.Text    = 'Connect to Unified Access Gateway (admin port)'
$cUAG.Use.Checked = $state.UseUAG
$cUAG.Server.Text = $state.UAGServer
$cUAG.User.Text   = $state.UAGUser
$cUAG.SkipCert.Checked = $state.UAGSkipCert
$tabUAG.Controls.Add((New-Label 'Admin port' 480 50 60))
$cUAG.Port = New-TextBox 540 48 60 ($state.UAGPort.ToString())
$tabUAG.Controls.Add($cUAG.Port)

# ---- DEM tab: filesystem-based, so no credential panel; just shares + optional agent probe target
$tabDEM = New-Object System.Windows.Forms.TabPage; $tabDEM.Text = 'DEM'; $tabs.TabPages.Add($tabDEM)
$cDEM = @{}
$cDEM.Use = New-Object System.Windows.Forms.CheckBox
$cDEM.Use.Text     = 'Scan VMware Dynamic Environment Manager (FlexEngine) shares'
$cDEM.Use.Location = New-Object System.Drawing.Point(20, 18); $cDEM.Use.Size = New-Object System.Drawing.Size(540, 22)
$cDEM.Use.Checked  = $state.UseDEM
$tabDEM.Controls.Add($cDEM.Use)

$tabDEM.Controls.Add((New-Label 'DEM Configuration Share (UNC, e.g. \\fs01\dem-config):' 14 50 460))
$cDEM.ConfigShare = New-TextBox 14 72 540 $state.DEMConfigShare
$tabDEM.Controls.Add($cDEM.ConfigShare)

$tabDEM.Controls.Add((New-Label 'DEM Profile / Archive Share (UNC, e.g. \\fs01\dem-profiles) - blank if NoAD-mode:' 14 104 540))
$cDEM.ArchiveShare = New-TextBox 14 126 540 $state.DEMArchiveShare
$tabDEM.Controls.Add($cDEM.ArchiveShare)

$tabDEM.Controls.Add((New-Label 'Agent Probe Target (optional VM FQDN; blank = skip agent-side scan):' 14 158 540))
$cDEM.AgentTarget = New-TextBox 14 180 540 $state.DEMAgentTarget
$tabDEM.Controls.Add($cDEM.AgentTarget)

$cDEM.Test = New-Object System.Windows.Forms.Button
$cDEM.Test.Text     = 'Test Reachability'
$cDEM.Test.Location = New-Object System.Drawing.Point(14, 215); $cDEM.Test.Size = New-Object System.Drawing.Size(160, 28)
$cDEM.Test.Add_Click({
    $msg = New-Object System.Text.StringBuilder
    foreach ($probe in @(@{Label='Config'; Path=$cDEM.ConfigShare.Text}, @{Label='Archive'; Path=$cDEM.ArchiveShare.Text})) {
        if (-not $probe.Path) { [void]$msg.AppendLine("$($probe.Label): not set"); continue }
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $ok = Test-Path $probe.Path -ErrorAction Stop
            $sw.Stop()
            [void]$msg.AppendLine("$($probe.Label): $($probe.Path) -> reachable=$ok ($($sw.ElapsedMilliseconds) ms)")
        } catch { [void]$msg.AppendLine("$($probe.Label): $($probe.Path) -> ERROR $($_.Exception.Message)") }
    }
    if ($cDEM.AgentTarget.Text) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.ReceiveTimeout = 4000
            $iar = $tcp.BeginConnect($cDEM.AgentTarget.Text, 5985, $null, $null)
            if ($iar.AsyncWaitHandle.WaitOne(4000)) { $tcp.EndConnect($iar); [void]$msg.AppendLine("Agent target $($cDEM.AgentTarget.Text):5985 (WinRM HTTP) reachable") }
            else { [void]$msg.AppendLine("Agent target $($cDEM.AgentTarget.Text):5985 timed out") }
        } catch { [void]$msg.AppendLine("Agent target: $($_.Exception.Message)") }
        finally { try { $tcp.Close() } catch { } }
    }
    [System.Windows.Forms.MessageBox]::Show($msg.ToString(), 'DEM Reachability Test', 'OK', 'Information') | Out-Null
})
$tabDEM.Controls.Add($cDEM.Test)

$tabNSX = New-Object System.Windows.Forms.TabPage; $tabNSX.Text = 'NSX';         $tabs.TabPages.Add($tabNSX)
$cNSX = New-PanelControls $tabNSX $false
$cNSX.Use.Text    = 'Connect to NSX Manager'
$cNSX.Use.Checked = $state.UseNSX
$cNSX.Server.Text = $state.NSXServer
$cNSX.User.Text   = $state.NSXUser
$cNSX.SkipCert.Checked = $state.NSXSkipCert

# ---- Wire profile pickers per tab ---------------------------------------
# Each tab calls Register-ProfileButtons with a TypeFilter (which profile
# Types are relevant to that tab) + a default Type to use when the operator
# clicks Save... TypeFilter is a soft filter - 'Other' is always shown too.
Register-ProfileButtons $cHV  -TypeFilter @('Domain','Local','Other')              -SuggestedType 'Domain'     -Label 'Horizon'
Register-ProfileButtons $cVC  -TypeFilter @('vCenterSSO','Domain','Local','Other') -SuggestedType 'vCenterSSO' -Label 'vCenter'
Register-ProfileButtons $cAV  -TypeFilter @('Domain','Local','Other')              -SuggestedType 'Domain'     -Label 'AppVolumes'
Register-ProfileButtons $cNTNX -TypeFilter @('Local','Domain','Other')             -SuggestedType 'Local'      -Label 'Nutanix'
Register-ProfileButtons $cVIDM -TypeFilter @('API','Other')                        -SuggestedType 'API'        -Label 'vIDM'
Register-ProfileButtons $cUEM  -TypeFilter @('API','Local','Other')                -SuggestedType 'API'        -Label 'WS1 UEM'
Register-ProfileButtons $cUAG -TypeFilter @('Local','API','Other')                 -SuggestedType 'Local'      -Label 'UAG'
Register-ProfileButtons $cNSX -TypeFilter @('Local','API','Other')                 -SuggestedType 'Local'      -Label 'NSX'

# Update Disable-Tab to also disable the new profile buttons when a tab is locked
# ---- Hard-lock tabs not selected on the starter --------------------------
# If the user did NOT pick a target on the starter dialog, that tab is
# disabled here (Use checkbox locked OFF, all controls greyed out, "[NOT
# SELECTED]" label shown). The category-scope filter in the runspace then
# guarantees those plugins never execute, even if state ever drifted.
function Disable-Tab($ctrls, $tabPage) {
    $ctrls.Use.Checked = $false
    $ctrls.Use.Enabled = $false
    foreach ($k in @('Server','User','Pass','Domain','SkipCert','Test','Port','UseProfile','SaveProfile')) {
        if ($ctrls.ContainsKey($k) -and $ctrls[$k]) {
            $ctrls[$k].Enabled = $false
            if ($ctrls[$k].GetType().Name -eq 'TextBox') { $ctrls[$k].Clear() }
        }
    }
    $note = New-Object System.Windows.Forms.Label
    $note.Text = '[NOT SELECTED on starter dialog - this target is disabled for this session]'
    $note.Location = New-Object System.Drawing.Point(140, 200)
    $note.Size     = New-Object System.Drawing.Size(500, 22)
    $note.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
    $note.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Italic)
    $tabPage.Controls.Add($note)
    $tabPage.Text = $tabPage.Text + ' (off)'
}
if (-not $state.UseHorizon) { Disable-Tab $cHV  $tabHV  }
if (-not $state.UseVCenter) { Disable-Tab $cVC  $tabVC  }
if (-not $state.UseAV)      { Disable-Tab $cAV  $tabAV  }
if (-not $state.UseNTNX)    { Disable-Tab $cNTNX $tabNTNX }
if (-not $state.UseVIDM)    { Disable-Tab $cVIDM $tabVIDM }
if (-not $state.UseUEM)     { Disable-Tab $cUEM  $tabUEM  }
if (-not $state.UseUAG)     { Disable-Tab $cUAG $tabUAG }
if (-not $state.UseNSX)     { Disable-Tab $cNSX $tabNSX }
if (-not $state.UseAD) {
    # AD tab uses a different shape (multi-row grid, no Server/User/Pass)
    # so Disable-Tab's Server/User/Pass.Clear() doesn't apply. Just append
    # the (off) suffix and disable the action buttons.
    $cAD.Use.Checked = $false
    foreach ($k in @('BtnAdd','BtnCred','BtnRemove','BtnTest')) { if ($cAD[$k]) { $cAD[$k].Enabled = $false } }
    $cAD.Grid.Enabled = $false
    $tabAD.Text = $tabAD.Text + ' (off)'
}
# Each tab page gets AutoScroll so its panels can scroll independently when
# the window is shorter than the tab's content. Important for jumpboxes /
# seamless RDP at 1366x768 where the form had clipped controls off-screen
# with no way to reach them. AutoScrollMinSize captures the in-page content
# height so PowerShell knows when to show the scrollbar.
foreach ($tp in @($tabHV, $tabVC, $tabAV, $tabNTNX, $tabVIDM, $tabUEM, $tabUAG, $tabNSX, $tabDEM, $tabLic, $tabAD)) {
    if ($tp) {
        $tp.AutoScroll = $true
        $tp.AutoScrollMinSize = New-Object System.Drawing.Size(840, 340)
    }
}

if (-not $state.UseDEM) {
    $cDEM.Use.Checked = $false; $cDEM.Use.Enabled = $false
    foreach ($k in @('ConfigShare','ArchiveShare','AgentTarget','Test')) { if ($cDEM[$k]) { $cDEM[$k].Enabled = $false; if ($cDEM[$k].GetType().Name -eq 'TextBox') { $cDEM[$k].Clear() } } }
    $note = New-Object System.Windows.Forms.Label
    $note.Text = '[NOT SELECTED on starter dialog - this target is disabled for this session]'
    $note.Location = New-Object System.Drawing.Point(140, 240); $note.Size = New-Object System.Drawing.Size(500, 22)
    $note.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
    $note.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Italic)
    $tabDEM.Controls.Add($note)
    $tabDEM.Text = $tabDEM.Text + ' (off)'
}

# Auto-jump to the first selected tab so the user lands on a useful one.
if     ($state.UseHorizon) { $tabs.SelectedTab = $tabHV  }
elseif ($state.UseVCenter) { $tabs.SelectedTab = $tabVC  }
elseif ($state.UseAV)      { $tabs.SelectedTab = $tabAV  }
elseif ($state.UseNTNX)    { $tabs.SelectedTab = $tabNTNX }
elseif ($state.UseVIDM)    { $tabs.SelectedTab = $tabVIDM }
elseif ($state.UseUEM)     { $tabs.SelectedTab = $tabUEM  }
elseif ($state.UseUAG)     { $tabs.SelectedTab = $tabUAG }
elseif ($state.UseNSX)     { $tabs.SelectedTab = $tabNSX }
elseif ($state.UseDEM)     { $tabs.SelectedTab = $tabDEM }

# ---- Output ---------------------------------------------------------------
$grpOut = New-Object System.Windows.Forms.GroupBox
$grpOut.Text = ' Output '
$grpOut.Location = New-Object System.Drawing.Point(12, 324)
$grpOut.Size     = New-Object System.Drawing.Size(870, 100)
$form.Controls.Add($grpOut)
$grpOut.Controls.Add((New-Label 'Output folder' 14 26))
$tbOutPath = New-TextBox 140 24 580 $state.OutputPath
$grpOut.Controls.Add($tbOutPath)
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse...'
$btnBrowse.Location = New-Object System.Drawing.Point(726, 22); $btnBrowse.Size = New-Object System.Drawing.Size(78, 24)
$grpOut.Controls.Add($btnBrowse)
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.SelectedPath = $tbOutPath.Text
    if ($dlg.ShowDialog() -eq 'OK') { $tbOutPath.Text = $dlg.SelectedPath }
})
$cbHtml     = New-CheckBox 'Generate HTML report' 140 56 180 $state.GenerateHtml
$cbWord     = New-CheckBox 'Generate Word .docx'  320 56 180 $state.GenerateWord
$cbShowWord = New-CheckBox 'Show Word window'     500 56 160 $state.ShowWord
$grpOut.Controls.Add($cbHtml); $grpOut.Controls.Add($cbWord); $grpOut.Controls.Add($cbShowWord)
$grpOut.Controls.Add((New-Label 'Doc author' 14 78 100))
# Doc Author defaults to the licensed user's email (Claims.sub) so reports
# are auto-attributed to whoever activated the license. Falls back to the
# saved state value if the license check fails or the field has been
# customized previously. Operator can always overwrite the textbox.
$defaultAuthor = $state.DocAuthor
try {
    $licCheck = Get-AGLicense -ErrorAction SilentlyContinue
    if ($licCheck -and $licCheck.Status -eq 'Active' -and $licCheck.Claims -and $licCheck.Claims.sub) {
        $licEmail = [string]$licCheck.Claims.sub
        # Only override the saved state if the user never set a custom
        # author OR the saved value still equals the legacy default.
        if (-not $state.DocAuthor -or $state.DocAuthor -eq 'AuthorityGate') {
            $defaultAuthor = $licEmail
        }
    }
} catch { }
$tbAuthor = New-TextBox 140 76 240 $defaultAuthor
$grpOut.Controls.Add($tbAuthor)

# ---- Plugin tree ----------------------------------------------------------
$grpPlug = New-Object System.Windows.Forms.GroupBox
$grpPlug.Text = ' Plugins (uncheck to skip) '
$grpPlug.Location = New-Object System.Drawing.Point(12, 430)
$grpPlug.Size     = New-Object System.Drawing.Size(870, 188)
# Plugin tree group is the resize-absorber: when the user makes the window
# taller it grows downward, when wider it grows rightward. Everything below
# it is bottom-anchored, so the tree stretches into the freed space.
$grpPlug.Anchor   = [System.Windows.Forms.AnchorStyles]::Top    -bor `
                    [System.Windows.Forms.AnchorStyles]::Bottom -bor `
                    [System.Windows.Forms.AnchorStyles]::Left   -bor `
                    [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($grpPlug)

$tree = New-Object System.Windows.Forms.TreeView
$tree.Location = New-Object System.Drawing.Point(12, 22)
$tree.Size     = New-Object System.Drawing.Size(846, 156)
$tree.Anchor   = [System.Windows.Forms.AnchorStyles]::Top    -bor `
                 [System.Windows.Forms.AnchorStyles]::Bottom -bor `
                 [System.Windows.Forms.AnchorStyles]::Left   -bor `
                 [System.Windows.Forms.AnchorStyles]::Right
$tree.CheckBoxes = $true
$grpPlug.Controls.Add($tree)
$pluginRoot = Join-Path $root 'Plugins'
$disabledSet = @{}
foreach ($d in @($state.DisabledPlugins)) { if ($d) { $disabledSet[$d] = $true } }
if (Test-Path $pluginRoot) {
    Get-ChildItem -Path $pluginRoot -Directory | Sort-Object Name | ForEach-Object {
        $cat = $_
        $catNode = $tree.Nodes.Add($cat.Name, $cat.Name)
        $catNode.Tag = "CATEGORY:$($cat.Name)"
        $catNode.Checked = $true
        Get-ChildItem -Path $cat.FullName -Filter *.ps1 | Sort-Object Name | ForEach-Object {
            $rel = "$($cat.Name)\$($_.Name)"
            $n = $catNode.Nodes.Add($rel, $_.BaseName)
            $n.Tag = $rel
            $n.Checked = -not $disabledSet.ContainsKey($rel)
            if (-not $n.Checked) { $catNode.Checked = $false }
        }
    }
}
$tree.Add_AfterCheck({
    param($s, $e)
    if ($e.Action -ne [System.Windows.Forms.TreeViewAction]::Unknown -and $e.Node.Tag -like 'CATEGORY:*') {
        foreach ($c in $e.Node.Nodes) { $c.Checked = $e.Node.Checked }
    }
})

# ---- Auto-uncheck plugin categories that aren't in scope -----------------
# Each category folder is mapped to one or more scope-toggle checkboxes
# (Horizon, vCenter, App Volumes, etc.). When ALL of a category's required
# scopes are unchecked, that category's plugins are auto-unchecked AND
# disabled in the tree so the user can see "this is out of scope, not just
# turned off." When a scope flips back on, plugins are restored unless the
# user had them in their persistent disabled-set.
#
# Categories NOT in this map are always-on (00 Initialize, 99 Disconnect,
# AD/DNS/DHCP/MFA/CA/Imprivata cross-cutting plugins). The user can still
# manually uncheck them.
$Script:CategoryScopeMap = @{
    '10 Connection Servers'           = @('HV')
    '20 Cloud Pod Architecture'       = @('HV')
    '30 Desktop Pools'                = @('HV')
    '40 RDS Farms'                    = @('HV')
    '50 Machines'                     = @('HV')
    '60 Sessions'                     = @('HV')
    '70 Events'                       = @('HV')
    '80 Licensing and Certificates'   = @('HV')
    '90 Gateways'                     = @('HV','UAG')
    '93 Enrollment Server'            = @('HV')
    '91 App Volumes'                  = @('AV')
    '92 Dynamic Environment Manager'  = @('DEM')
    '94 NSX'                          = @('NSX')
    '95 vSphere Backing Infra'        = @('VC')
    '96 vSphere Standalone'           = @('VC')
    '97 vSphere for Horizon'          = @('VC')
    '97 Nutanix Prism'                = @('NTNX')
    '98 vSAN'                         = @('VC')
    '99 vSphere Lifecycle'            = @('VC')
    'A0 Hardware'                     = @('VC')
    'B1 Identity Manager'             = @('VIDM')
    'B3 Active Directory'             = @('AD')
    'B4 DNS DHCP'                     = @('AD')
    'B5 Workspace ONE Access'         = @('VIDM')
    'B6 Workspace ONE UEM'            = @('UEM')
    'B7 Backup and DR'                = @('VC')
    'B8 FSLogix'                      = @('HV')
    'C0 SQL Server Health'            = @('VC')
    'C1 Identity Federation'          = @('VIDM')
    'C2 Hardening Guide'              = @('VC')
    'C3 License Lifecycle'            = @('HV')
}

function Global:Update-PluginScope {
    # Snapshot which scopes are currently on, then walk every category
    # node and toggle its Checked + Enabled state to match.
    $scopeOn = @{
        HV   = $cHV.Use.Checked
        VC   = $cVC.Use.Checked
        AV   = $cAV.Use.Checked
        UAG  = $cUAG.Use.Checked
        NSX  = $cNSX.Use.Checked
        DEM  = $cDEM.Use.Checked
        NTNX = $cNTNX.Use.Checked
        VIDM = $cVIDM.Use.Checked
        UEM  = $cUEM.Use.Checked
        AD   = if ($cAD -and $cAD.Use) { $cAD.Use.Checked } else { $false }
    }
    foreach ($catNode in $tree.Nodes) {
        if ($catNode.Tag -notlike 'CATEGORY:*') { continue }
        $catName = $catNode.Tag.Substring(9)
        if (-not $Script:CategoryScopeMap.ContainsKey($catName)) {
            # Always-on category - leave as-is
            $catNode.ForeColor = [System.Drawing.SystemColors]::WindowText
            continue
        }
        $reqScopes = @($Script:CategoryScopeMap[$catName])
        $anyOn = $false
        foreach ($sk in $reqScopes) { if ($scopeOn[$sk]) { $anyOn = $true; break } }
        if (-not $anyOn) {
            # Out of scope - hard-uncheck and grey out
            foreach ($plug in $catNode.Nodes) {
                $plug.Checked = $false
                $plug.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 160)
            }
            $catNode.Checked = $false
            $catNode.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 160)
        } else {
            # In scope - restore default-color and tick anything not in
            # the persistent disabled-set
            $allOn = $true
            foreach ($plug in $catNode.Nodes) {
                $plug.ForeColor = [System.Drawing.SystemColors]::WindowText
                $rel = [string]$plug.Tag
                $inDisabled = ($rel -and $disabledSet.ContainsKey($rel))
                $plug.Checked = -not $inDisabled
                if ($inDisabled) { $allOn = $false }
            }
            $catNode.Checked = $allOn
            $catNode.ForeColor = [System.Drawing.SystemColors]::WindowText
        }
    }
}

# Wire the scope-checkbox CheckedChanged events. Capture-by-closure so the
# handlers find the right $tree + map at fire time.
foreach ($cb in @($cHV.Use, $cVC.Use, $cAV.Use, $cUAG.Use, $cNSX.Use, $cDEM.Use, $cNTNX.Use, $cVIDM.Use, $cUEM.Use, $cAD.Use)) {
    $cb.Add_CheckedChanged({ Update-PluginScope }.GetNewClosure())
}
# Initial sync so the tree reflects the starter dialog's scope picks.
Update-PluginScope

# ---- Scope row: live indicator + quick-select buttons --------------------
# Sits between plugin tree (ends y=618) and progress bar row (y=662).
$scopeRow = New-Object System.Windows.Forms.Panel
$scopeRow.Location = New-Object System.Drawing.Point(12, 624)
$scopeRow.Size     = New-Object System.Drawing.Size(870, 32)
$scopeRow.Anchor   = [System.Windows.Forms.AnchorStyles]::Bottom -bor `
                     [System.Windows.Forms.AnchorStyles]::Left   -bor `
                     [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($scopeRow)

$lblScope = New-Object System.Windows.Forms.Label
$lblScope.Location = New-Object System.Drawing.Point(0, 6)
$lblScope.Size     = New-Object System.Drawing.Size(380, 22)
$lblScope.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$scopeRow.Controls.Add($lblScope)

function Global:Update-ScopeLabel {
    $s = @()
    if ($cHV.Use.Checked  -and $cHV.Server.Text)  { $s += 'Horizon' }
    if ($cVC.Use.Checked  -and $cVC.Server.Text)  { $s += 'vCenter' }
    if ($cAV.Use.Checked  -and $cAV.Server.Text)  { $s += 'App Volumes' }
    if ($cUAG.Use.Checked -and $cUAG.Server.Text) { $s += 'UAG' }
    if ($cNSX.Use.Checked -and $cNSX.Server.Text) { $s += 'NSX' }
    if ($cNTNX -and $cNTNX.Use.Checked  -and $cNTNX.Server.Text)  { $s += 'Nutanix' }
    if ($cVIDM -and $cVIDM.Use.Checked  -and $cVIDM.Server.Text)  { $s += 'vIDM' }
    if ($cUEM  -and $cUEM.Use.Checked   -and $cUEM.Server.Text)   { $s += 'WS1 UEM' }
    if ($cDEM  -and $cDEM.Use.Checked   -and ($cDEM.ConfigShare.Text -or $cDEM.ArchiveShare.Text)) { $s += 'DEM' }
    # AD has no Server textbox; the source of truth is the AD-tab DataGridView.
    # Any row with a non-empty DC/Server value counts as AD scope active.
    if ($cAD -and $cAD.Use.Checked -and $cAD.Grid -and $cAD.Grid.Rows.Count -gt 0) {
        $adRows = 0
        foreach ($r in $cAD.Grid.Rows) {
            if ($r.IsNewRow) { continue }
            $dcVal = $null
            try { $dcVal = $r.Cells['colDC'].Value } catch { }
            if (-not $dcVal) { try { $dcVal = $r.Cells[0].Value } catch { } }
            if ($dcVal -and "$dcVal".Trim()) { $adRows++ }
        }
        if ($adRows -gt 0) { $s += 'AD' }
    }
    if ($s.Count -eq 0) {
        $lblScope.Text = 'Scope: NONE - tick a tab or use a quick-select button'
        $lblScope.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
    } else {
        $lblScope.Text = 'Scope: ' + ($s -join ', ')
        $lblScope.ForeColor = [System.Drawing.Color]::FromArgb(0, 100, 0)
    }
}

# Wire each tab's Use checkbox + relevant text/grid event to refresh the
# scope label. AD wires to the grid's Rows-changed events instead of a
# Server textbox; DEM wires to its share textboxes; the rest wire to
# Server.
foreach ($pair in @(@($cHV,'Server'),@($cVC,'Server'),@($cAV,'Server'),@($cUAG,'Server'),@($cNSX,'Server'),@($cNTNX,'Server'),@($cVIDM,'Server'),@($cUEM,'Server'))) {
    if (-not $pair[0]) { continue }
    $pair[0].Use.Add_CheckedChanged({ Update-ScopeLabel }.GetNewClosure())
    if ($pair[0].Server) {
        $pair[0].Server.Add_TextChanged({ Update-ScopeLabel }.GetNewClosure())
    }
}
if ($cDEM) {
    $cDEM.Use.Add_CheckedChanged({ Update-ScopeLabel }.GetNewClosure())
    if ($cDEM.ConfigShare)  { $cDEM.ConfigShare.Add_TextChanged({ Update-ScopeLabel }.GetNewClosure()) }
    if ($cDEM.ArchiveShare) { $cDEM.ArchiveShare.Add_TextChanged({ Update-ScopeLabel }.GetNewClosure()) }
}
if ($cAD) {
    $cAD.Use.Add_CheckedChanged({ Update-ScopeLabel }.GetNewClosure())
    if ($cAD.Grid) {
        $cAD.Grid.Add_RowsAdded({ Update-ScopeLabel }.GetNewClosure())
        $cAD.Grid.Add_RowsRemoved({ Update-ScopeLabel }.GetNewClosure())
        $cAD.Grid.Add_CellValueChanged({ Update-ScopeLabel }.GetNewClosure())
    }
}

# Quick-select buttons
function New-ScopeButton($text, $x, $action) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, 4)
    $b.Size     = New-Object System.Drawing.Size(100, 24)
    $b.FlatStyle = 'Flat'
    $b.Add_Click($action)
    $b
}

# A "Restart" button to re-show the starter dialog (= change scope).
# Anchored Top|Right so it tracks the right edge when the scope row widens.
$btnRestart = New-ScopeButton 'Change Scope...' 700 {
    $form.Close()
    Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath)
}
$btnRestart.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$scopeRow.Controls.Add($btnRestart)

Update-ScopeLabel

# ---- Bottom row: Run / Open / Close + log -------------------------------
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = 'Run Health Check'
$btnRun.Location = New-Object System.Drawing.Point(12, 692)
$btnRun.Size     = New-Object System.Drawing.Size(160, 32)
$btnRun.BackColor = [System.Drawing.Color]::FromArgb(10,61,98)
$btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.FlatStyle = 'Flat'
$btnRun.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$form.Controls.Add($btnRun)

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = 'Open Last Report'
$btnOpen.Location = New-Object System.Drawing.Point(180, 692)
$btnOpen.Size     = New-Object System.Drawing.Size(140, 32)
$btnOpen.Enabled = $false
$btnOpen.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$form.Controls.Add($btnOpen)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(802, 692)
$btnClose.Size     = New-Object System.Drawing.Size(80, 32)
$btnClose.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

# ---- Optional: in-guest deep-scan credentials ---------------------------
# When set, gold-image / RDSH-master / AV-packaging deep-scan plugins probe
# the guest via WinRM (Tier 2). Without this they emit Tier 1 only.
$Script:ImageScanCred = $null
$btnImgCred = New-Object System.Windows.Forms.Button
$btnImgCred.Text = 'Set Deep-Scan Creds...'
$btnImgCred.Location = New-Object System.Drawing.Point(330, 692)
$btnImgCred.Size     = New-Object System.Drawing.Size(170, 32)
$btnImgCred.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnImgCred.Add_Click({
    param($sender,$e)
    $btn = $sender
    # Click drops a context menu: pick profile, prompt manually, or open mgr.
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $profiles = @(Get-AGCredentialProfile | Where-Object { $_.Type -in 'Local','Domain','Other' } | Sort-Object Name)
    foreach ($p in $profiles) {
        $mi = $menu.Items.Add("Use profile: $($p.Name)  -  $($p.UserName)  [$($p.Type)]")
        # Tag carries both the button reference and the profile name so the
        # handler doesn't depend on PowerShell closure scope (which gets
        # eaten by WinForms' event-dispatch boundary).
        $mi.Tag = @{ Profile = $p.Name; Button = $btn }
        $mi.Add_Click({
            param($s,$e2)
            $tag = $s.Tag
            if (-not $tag) { return }
            $c = $null
            try {
                $c = Get-AGCredentialAsPSCredential -Name $tag.Profile
            } catch {
                [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Profile decrypt failed', 'OK', 'Error') | Out-Null
                return
            }
            if (-not $c) { return }
            $Script:ImageScanCred = $c
            $b = $tag.Button
            if ($b) {
                $b.Text = "Creds: $($c.UserName)"
                $b.BackColor = [System.Drawing.Color]::FromArgb(39, 174, 96)
                $b.ForeColor = [System.Drawing.Color]::White
            }
        })
    }
    if ($profiles.Count -gt 0) { $menu.Items.Add('-') | Out-Null }
    $miNew = $menu.Items.Add('Enter credential manually...')
    $miNew.Tag = @{ Button = $btn }
    $miNew.Add_Click({
        param($s,$e2)
        $b = if ($s.Tag) { $s.Tag.Button } else { $null }
        $c = Get-Credential -Message "Windows credential with WinRM rights to gold / RDSH / packaging VMs (e.g. DOMAIN\image-scan-svc OR .\Administrator for local). Cancel = skip Tier 2 deep scan."
        if ($c) {
            $Script:ImageScanCred = $c
            if ($b) {
                $b.Text = "Creds: $($c.UserName)"
                $b.BackColor = [System.Drawing.Color]::FromArgb(39, 174, 96)
                $b.ForeColor = [System.Drawing.Color]::White
            }
            if ([System.Windows.Forms.MessageBox]::Show("Save these credentials as a named profile so they're reusable?", 'Save profile', 'YesNo', 'Question') -eq 'Yes') {
                $name = Read-NameDialog -Title 'Save credential profile' -Prompt 'Name this profile (visible in the Profile menu next time):' -DefaultValue "DeepScan - $($c.UserName)"
                if ($name) {
                    $type = if ($c.UserName -match '^\.\\|^[^\\@]+$') { 'Local' } else { 'Domain' }
                    Set-AGCredentialProfile -Name $name -Credential $c -Type $type -Notes 'Saved from Deep-Scan creds button' | Out-Null
                }
            }
        }
    })
    $miMgr = $menu.Items.Add('Manage Credentials...')
    $miMgr.Add_Click({ Show-CredentialProfileDialog })
    $menu.Show($btn, 0, $btn.Height)
})
$form.Controls.Add($btnImgCred)

$lblImgCred = New-Object System.Windows.Forms.Label
$lblImgCred.Text = '(optional - enables in-guest gold image scan)'
$lblImgCred.Location = New-Object System.Drawing.Point(508, 700)
$lblImgCred.Size     = New-Object System.Drawing.Size(290, 18)
$lblImgCred.ForeColor = [System.Drawing.Color]::FromArgb(96, 96, 96)
$lblImgCred.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$form.Controls.Add($lblImgCred)

# ---- Specialized scopes (AD / MFA / Imprivata / DEM) --------------------
# These plugins fire only when the operator supplies a config hint. Without
# this dialog, the operator would have to set $Global:* variables in
# PowerShell - which they will not. The button opens a dialog with one
# field per specialized scope; values flow into the runspace via
# SetVariable and the matching plugins read $Global:* at execution time.
$Script:SpecImprivata = ''
$Script:SpecDEMShare  = ''
$Script:SpecADForest  = ''
$Script:SpecADCredential = $null
$Script:SpecAVPackagingVms = ''
$Script:SpecMFAExternalCheck = $false
$Script:CustomerName  = ''

$btnSpec = New-Object System.Windows.Forms.Button
$btnSpec.Text = 'Configure Specialized Scopes...'
$btnSpec.Location = New-Object System.Drawing.Point(12, 732)
$btnSpec.Size     = New-Object System.Drawing.Size(220, 28)
$btnSpec.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$btnSpec.FlatStyle = 'Flat'
$btnSpec.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnSpec.Add_Click({
    # Build dialog
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Specialized Scope Configuration'
    $dlg.Size = New-Object System.Drawing.Size(640, 510)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'Sizable'
    $dlg.MaximizeBox = $true
    $dlg.MinimumSize = New-Object System.Drawing.Size(500, 400)
    $dlg.AutoScroll = $true
    $dlg.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Location = New-Object System.Drawing.Point(14, 12)
    $intro.Size     = New-Object System.Drawing.Size(610, 50)
    $intro.Text = 'These scopes are skipped by default. Configure only what applies to this engagement. Empty fields = scope skipped (no findings emitted from those plugins).'
    $intro.ForeColor = [System.Drawing.Color]::FromArgb(96, 96, 96)
    $dlg.Controls.Add($intro)

    # Customer Name
    $lblCust = New-Object System.Windows.Forms.Label
    $lblCust.Text = 'Customer / Engagement Name (optional - flows into report cover):'
    $lblCust.Location = New-Object System.Drawing.Point(14, 66); $lblCust.Size = New-Object System.Drawing.Size(600, 18)
    $dlg.Controls.Add($lblCust)
    $tbCust = New-Object System.Windows.Forms.TextBox
    $tbCust.Location = New-Object System.Drawing.Point(14, 86); $tbCust.Size = New-Object System.Drawing.Size(600, 22)
    $tbCust.Text = $Script:CustomerName
    $dlg.Controls.Add($tbCust)

    # Active Directory configuration moved to the dedicated 'AD' tab on the
    # main form (multi-forest list + per-row credential profiles + Test).
    # The legacy single-forest field below is kept for state.json files
    # written by older builds; it's read-only and grey to discourage use.
    $lblAD = New-Object System.Windows.Forms.Label
    $lblAD.Text = "Active Directory: configure on the AD tab of the main form (multi-forest list, separate DC + Forest fields, per-row credentials)."
    $lblAD.Location = New-Object System.Drawing.Point(14, 116); $lblAD.Size = New-Object System.Drawing.Size(600, 32)
    $lblAD.ForeColor = [System.Drawing.Color]::FromArgb(96, 96, 96)
    $lblAD.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Italic)
    $dlg.Controls.Add($lblAD)
    # Legacy fallback (hidden) - kept so the state.json migration path works.
    $tbAD = New-Object System.Windows.Forms.TextBox
    $tbAD.Visible = $false
    $tbAD.Text = $Script:SpecADForest
    $dlg.Controls.Add($tbAD)
    $btnADCred = New-Object System.Windows.Forms.Button
    $btnADCred.Visible = $false
    $btnADCred.Text = 'Set AD Cred...'
    # Store the button reference on its own Tag so menu-item handlers can
    # find it without relying on PowerShell closure scope (which gets eaten
    # by WinForms' event-dispatch boundary in some PS5.1 builds).
    $btnADCred.Tag = @{ Self = $btnADCred }
    $btnADCred.Add_Click({
        param($sender,$e)
        $btn = $sender    # the button itself
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $profiles = @(Get-AGCredentialProfile | Where-Object { $_.Type -in 'Domain','Other' } | Sort-Object Name)
        foreach ($p in $profiles) {
            $mi = $menu.Items.Add("Use profile: $($p.Name)  -  $($p.UserName)")
            # Each menu item carries the button reference + profile name so
            # the click handler doesn't need closure scope to find them.
            $mi.Tag = @{ Profile = $p.Name; Button = $btn }
            $mi.Add_Click({
                param($s,$e2)
                $tag = $s.Tag
                if (-not $tag) { return }
                $c = $null
                try {
                    $c = Get-AGCredentialAsPSCredential -Name $tag.Profile
                } catch {
                    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Profile decrypt failed', 'OK', 'Error') | Out-Null
                    return
                }
                if (-not $c) { return }
                $Script:SpecADCredential = $c
                $b = $tag.Button
                if ($b) {
                    $b.Text = "Cred: $($c.UserName)"
                    $b.BackColor = [System.Drawing.Color]::FromArgb(39, 174, 96)
                    $b.ForeColor = [System.Drawing.Color]::White
                }
            })
        }
        if ($profiles.Count -gt 0) { $menu.Items.Add('-') | Out-Null }
        $miNew = $menu.Items.Add('Enter credential manually...')
        $miNew.Tag = @{ Button = $btn }
        $miNew.Add_Click({
            param($s,$e2)
            $b = if ($s.Tag) { $s.Tag.Button } else { $null }
            $c = Get-Credential -Message "AD credential for the forest hint above. UPN form: user@authoritygate.net"
            if ($c) {
                $Script:SpecADCredential = $c
                if ($b) {
                    $b.Text = "Cred: $($c.UserName)"
                    $b.BackColor = [System.Drawing.Color]::FromArgb(39, 174, 96)
                    $b.ForeColor = [System.Drawing.Color]::White
                }
                if ([System.Windows.Forms.MessageBox]::Show("Save these AD credentials as a named profile?", 'Save profile', 'YesNo', 'Question') -eq 'Yes') {
                    $name = Read-NameDialog -Title 'Save credential profile' -Prompt 'Name this profile:' -DefaultValue "AD - $($c.UserName)"
                    if ($name) {
                        Set-AGCredentialProfile -Name $name -Credential $c -Type 'Domain' -Notes 'Saved from AD cred button' | Out-Null
                    }
                }
            }
        })
        $miMgr = $menu.Items.Add('Manage Credentials...')
        $miMgr.Add_Click({ Show-CredentialProfileDialog })
        $menu.Show($btn, 0, $btn.Height)
    })
    $dlg.Controls.Add($btnADCred)
    # RSAT discovery + install moved to the AD tab on the main form (lives
    # next to the configuration that needs it).

    # MFA / External auth
    $cbMFA = New-Object System.Windows.Forms.CheckBox
    $cbMFA.Text = 'Probe configured MFA mechanisms (RADIUS, SAML, Smart Card) - reads from Horizon REST when Horizon connected'
    $cbMFA.Location = New-Object System.Drawing.Point(14, 188); $cbMFA.Size = New-Object System.Drawing.Size(600, 22)
    $cbMFA.Checked = $Script:SpecMFAExternalCheck
    $dlg.Controls.Add($cbMFA)

    # Imprivata
    $lblImp = New-Object System.Windows.Forms.Label
    $lblImp.Text = 'Imprivata Appliance URLs (one per line; e.g. https://imprivata-appliance.lab.local) - optional:'
    $lblImp.Location = New-Object System.Drawing.Point(14, 220); $lblImp.Size = New-Object System.Drawing.Size(600, 18)
    $dlg.Controls.Add($lblImp)
    $tbImp = New-Object System.Windows.Forms.TextBox
    $tbImp.Location = New-Object System.Drawing.Point(14, 240); $tbImp.Size = New-Object System.Drawing.Size(600, 50)
    $tbImp.Multiline = $true
    $tbImp.ScrollBars = 'Vertical'
    $tbImp.Text = $Script:SpecImprivata
    $dlg.Controls.Add($tbImp)

    # NOTE: DEM Configuration Share + App Volumes Packaging VM names moved
    # to their respective dedicated tabs (DEM tab + AppVolumes tab). The
    # $Script:SpecDEMShare and $Script:SpecAVPackagingVms variables are kept
    # only as fallbacks for state.json files that pre-date the move.

    # OK / Cancel
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'Save'
    $btnOk.Location = New-Object System.Drawing.Point(440, 432); $btnOk.Size = New-Object System.Drawing.Size(80, 28)
    $btnOk.Add_Click({
        $Script:CustomerName        = $tbCust.Text.Trim()
        $Script:SpecADForest        = $tbAD.Text.Trim()
        $Script:SpecMFAExternalCheck= $cbMFA.Checked
        $Script:SpecImprivata       = $tbImp.Text.Trim()
        # Note: SpecAVPackagingVms + SpecDEMShare moved to their own tabs;
        # they are no longer captured by this dialog.
        $dlg.DialogResult = 'OK'; $dlg.Close()
    })
    $dlg.Controls.Add($btnOk)
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Location = New-Object System.Drawing.Point(534, 432); $btnCancel.Size = New-Object System.Drawing.Size(80, 28)
    $btnCancel.Add_Click({ $dlg.DialogResult = 'Cancel'; $dlg.Close() })
    $dlg.Controls.Add($btnCancel)

    [void]$dlg.ShowDialog($form)

    # Update the main button label so user sees that scopes are configured
    $configured = @()
    if ($Script:CustomerName)        { $configured += 'Customer' }
    if ($Script:SpecADForest)        { $configured += 'AD' }
    if ($Script:SpecMFAExternalCheck){ $configured += 'MFA' }
    if ($Script:SpecImprivata)       { $configured += 'Imprivata' }
    if ($Script:SpecDEMShare)        { $configured += 'DEM' }
    if ($Script:SpecAVPackagingVms)  { $configured += 'AV-Pkg' }
    if ($configured.Count -gt 0) {
        $btnSpec.Text = "Specialized: $($configured -join ', ')"
        $btnSpec.BackColor = [System.Drawing.Color]::FromArgb(39, 174, 96)
        $btnSpec.ForeColor = [System.Drawing.Color]::White
    }
})
$form.Controls.Add($btnSpec)


# ---- Pick Gold Images dialog (separate button) --------------------------
# Connects on-demand to vCenter (using the creds already entered on the
# vCenter tab), pulls every VM, lets the operator check which are gold
# images. Shows PowerState + Tools state + last-snapshot age. Provides
# Power-On + Test-Reachability buttons. Selected names flow into
# $Global:HVManualGoldImageList which the deep-scan plugin consumes.
$Script:ManualGoldImages = @()
# Per-VM credential profile mapping. Keys = VM name, values = profile name.
# When a VM has an entry here, the deep-scan plugin uses that profile's cred
# instead of the global $Global:HVImageScanCredential. Lets gold images on
# different local-admin passwords be scanned in a single run.
$Script:ManualGoldImageCreds = @{}
# Manage Credentials button - opens the centralized credential profile store
Import-Module (Join-Path $root 'Modules\CredentialProfiles.psm1') -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $root 'Modules\Licensing.psm1') -Force -ErrorAction SilentlyContinue

$btnCreds = New-Object System.Windows.Forms.Button
$btnCreds.Text = 'Manage Credentials...'
$btnCreds.Location = New-Object System.Drawing.Point(414, 732)
$btnCreds.Size     = New-Object System.Drawing.Size(170, 28)
$btnCreds.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$btnCreds.FlatStyle = 'Flat'
$btnCreds.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnCreds.Add_Click({ Show-CredentialProfileDialog })
$form.Controls.Add($btnCreds)

function Global:Show-CredentialProfileDialog {
    $dlgC = New-Object System.Windows.Forms.Form
    $dlgC.Text = 'AuthorityGate Credential Profiles'
    $dlgC.Size = New-Object System.Drawing.Size(820, 560)
    $dlgC.StartPosition = 'CenterParent'
    $dlgC.FormBorderStyle = 'Sizable'
    $dlgC.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $lblHdr = New-Object System.Windows.Forms.Label
    $lblHdr.Text = 'Profiles are encrypted via Windows DPAPI (per-user, per-machine). They can be reused across vCenter / Horizon / AppVolumes / UAG / NSX / AD / gold-image scans.'
    $lblHdr.Location = New-Object System.Drawing.Point(14, 12)
    $lblHdr.Size     = New-Object System.Drawing.Size(780, 32)
    $lblHdr.ForeColor = [System.Drawing.Color]::FromArgb(96, 96, 96)
    $dlgC.Controls.Add($lblHdr)

    $lvC = New-Object System.Windows.Forms.ListView
    $lvC.Location = New-Object System.Drawing.Point(14, 50)
    $lvC.Size     = New-Object System.Drawing.Size(780, 380)
    $lvC.View = 'Details'; $lvC.FullRowSelect = $true; $lvC.GridLines = $true
    $lvC.Anchor = 'Top,Bottom,Left,Right'
    [void]$lvC.Columns.Add('Profile Name', 220)
    [void]$lvC.Columns.Add('User Name', 220)
    [void]$lvC.Columns.Add('Type', 90)
    [void]$lvC.Columns.Add('Notes', 240)
    $dlgC.Controls.Add($lvC)

    $populateC = {
        $lvC.Items.Clear()
        foreach ($p in (Get-AGCredentialProfile)) {
            $it = New-Object System.Windows.Forms.ListViewItem([string]$p.Name)
            [void]$it.SubItems.Add([string]$p.UserName)
            [void]$it.SubItems.Add([string]$p.Type)
            [void]$it.SubItems.Add([string]$p.Notes)
            [void]$lvC.Items.Add($it)
        }
    }
    & $populateC

    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = 'Add / Edit'
    $btnAdd.Location = New-Object System.Drawing.Point(14, 442); $btnAdd.Size = New-Object System.Drawing.Size(110, 28)
    $btnAdd.Anchor = 'Bottom,Left'
    $dlgC.Controls.Add($btnAdd)

    $btnDel = New-Object System.Windows.Forms.Button
    $btnDel.Text = 'Delete'
    $btnDel.Location = New-Object System.Drawing.Point(130, 442); $btnDel.Size = New-Object System.Drawing.Size(90, 28)
    $btnDel.Anchor = 'Bottom,Left'
    $dlgC.Controls.Add($btnDel)

    $btnExp = New-Object System.Windows.Forms.Button
    $btnExp.Text = 'Export...'
    $btnExp.Location = New-Object System.Drawing.Point(226, 442); $btnExp.Size = New-Object System.Drawing.Size(90, 28)
    $btnExp.Anchor = 'Bottom,Left'
    $dlgC.Controls.Add($btnExp)

    $btnImp = New-Object System.Windows.Forms.Button
    $btnImp.Text = 'Import...'
    $btnImp.Location = New-Object System.Drawing.Point(322, 442); $btnImp.Size = New-Object System.Drawing.Size(90, 28)
    $btnImp.Anchor = 'Bottom,Left'
    $dlgC.Controls.Add($btnImp)

    $lblPath = New-Object System.Windows.Forms.Label
    $lblPath.Text = "Store: $(Get-AGCredentialProfileStorePath)"
    $lblPath.Location = New-Object System.Drawing.Point(14, 478); $lblPath.Size = New-Object System.Drawing.Size(780, 16)
    $lblPath.Anchor = 'Bottom,Left,Right'
    $lblPath.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
    $lblPath.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $dlgC.Controls.Add($lblPath)

    $btnCloseC = New-Object System.Windows.Forms.Button
    $btnCloseC.Text = 'Close'
    $btnCloseC.Location = New-Object System.Drawing.Point(700, 442); $btnCloseC.Size = New-Object System.Drawing.Size(94, 28)
    $btnCloseC.Anchor = 'Bottom,Right'
    $btnCloseC.Add_Click({ $dlgC.Close() })
    $dlgC.Controls.Add($btnCloseC)

    $btnAdd.Add_Click({
        $existing = $null
        $editName = ''
        if ($lvC.SelectedItems.Count -gt 0) {
            $editName = $lvC.SelectedItems[0].Text
            $existing = Get-AGCredentialProfile -Name $editName
        }
        $r = Show-CredentialEditDialog -Existing $existing
        if ($r) {
            Set-AGCredentialProfile -Name $r.Name -Credential $r.Credential -Type $r.Type -Notes $r.Notes | Out-Null
            & $populateC
        }
    })
    $btnDel.Add_Click({
        if ($lvC.SelectedItems.Count -eq 0) { return }
        $name = $lvC.SelectedItems[0].Text
        if ([System.Windows.Forms.MessageBox]::Show("Delete profile '$name'?", 'Confirm', 'YesNo', 'Question') -eq 'Yes') {
            Remove-AGCredentialProfile -Name $name | Out-Null
            & $populateC
        }
    })
    $btnExp.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = 'JSON|*.json'; $sfd.FileName = 'authoritygate-credentials.json'
        if ($sfd.ShowDialog($dlgC) -eq 'OK') {
            $pp = Read-PassphraseDialog -Title 'Export passphrase' -Prompt 'Enter a passphrase to protect the export. You will need this same passphrase to import on another machine.'
            if ($pp) {
                try { Export-AGCredentialProfiles -Path $sfd.FileName -Passphrase $pp; [System.Windows.Forms.MessageBox]::Show("Exported.", 'Export', 'OK', 'Information') | Out-Null }
                catch { [System.Windows.Forms.MessageBox]::Show("Export failed: $($_.Exception.Message)", 'Export', 'OK', 'Error') | Out-Null }
            }
        }
    })
    $btnImp.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = 'JSON|*.json'
        if ($ofd.ShowDialog($dlgC) -eq 'OK') {
            $pp = Read-PassphraseDialog -Title 'Import passphrase' -Prompt 'Enter the passphrase used when exporting this file.'
            if ($pp) {
                try { Import-AGCredentialProfiles -Path $ofd.FileName -Passphrase $pp -Overwrite; & $populateC }
                catch { [System.Windows.Forms.MessageBox]::Show("Import failed: $($_.Exception.Message)", 'Import', 'OK', 'Error') | Out-Null }
            }
        }
    })

    [void]$dlgC.ShowDialog($form)
}

function Global:Show-CredentialEditDialog {
    param($Existing)
    $d = New-Object System.Windows.Forms.Form
    $d.Text = if ($Existing) { "Edit Profile: $($Existing.Name)" } else { 'New Credential Profile' }
    $d.Size = New-Object System.Drawing.Size(540, 360)
    $d.StartPosition = 'CenterParent'
    $d.FormBorderStyle = 'Sizable'
    $d.MaximizeBox = $true
    $d.MinimumSize = New-Object System.Drawing.Size(440, 300)
    $d.AutoScroll = $true
    $d.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $row = 14
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = 'Profile name (unique label):'
    $lbl.Location = New-Object System.Drawing.Point(14, $row); $lbl.Size = New-Object System.Drawing.Size(480, 18)
    $d.Controls.Add($lbl); $row += 20
    $tbName = New-Object System.Windows.Forms.TextBox
    $tbName.Location = New-Object System.Drawing.Point(14, $row); $tbName.Size = New-Object System.Drawing.Size(490, 22)
    if ($Existing) { $tbName.Text = $Existing.Name; $tbName.ReadOnly = $true }
    $d.Controls.Add($tbName); $row += 32

    $lbl2 = New-Object System.Windows.Forms.Label
    $lbl2.Text = 'User name (e.g. user@domain.com OR DOMAIN\user OR .\Administrator for local):'
    $lbl2.Location = New-Object System.Drawing.Point(14, $row); $lbl2.Size = New-Object System.Drawing.Size(490, 18)
    $d.Controls.Add($lbl2); $row += 20
    $tbUser = New-Object System.Windows.Forms.TextBox
    $tbUser.Location = New-Object System.Drawing.Point(14, $row); $tbUser.Size = New-Object System.Drawing.Size(490, 22)
    if ($Existing) { $tbUser.Text = $Existing.UserName }
    $d.Controls.Add($tbUser); $row += 32

    $lbl3 = New-Object System.Windows.Forms.Label
    $lbl3.Text = 'Password:'
    $lbl3.Location = New-Object System.Drawing.Point(14, $row); $lbl3.Size = New-Object System.Drawing.Size(490, 18)
    $d.Controls.Add($lbl3); $row += 20
    $tbPwd = New-Object System.Windows.Forms.TextBox
    $tbPwd.Location = New-Object System.Drawing.Point(14, $row); $tbPwd.Size = New-Object System.Drawing.Size(490, 22)
    $tbPwd.UseSystemPasswordChar = $true
    if ($Existing) { $tbPwd.Text = '<unchanged>' }   # placeholder
    $d.Controls.Add($tbPwd); $row += 32

    $lbl4 = New-Object System.Windows.Forms.Label
    $lbl4.Text = 'Type (helps GUI suggest the right profile per context):'
    $lbl4.Location = New-Object System.Drawing.Point(14, $row); $lbl4.Size = New-Object System.Drawing.Size(490, 18)
    $d.Controls.Add($lbl4); $row += 20
    $cbType = New-Object System.Windows.Forms.ComboBox
    $cbType.Location = New-Object System.Drawing.Point(14, $row); $cbType.Size = New-Object System.Drawing.Size(180, 22)
    $cbType.DropDownStyle = 'DropDownList'
    foreach ($t in 'Domain','Local','vCenterSSO','API','Other') { [void]$cbType.Items.Add($t) }
    $cbType.SelectedItem = if ($Existing) { $Existing.Type } else { 'Domain' }
    $d.Controls.Add($cbType); $row += 32

    $lbl5 = New-Object System.Windows.Forms.Label
    $lbl5.Text = 'Notes (operator-facing description):'
    $lbl5.Location = New-Object System.Drawing.Point(14, $row); $lbl5.Size = New-Object System.Drawing.Size(490, 18)
    $d.Controls.Add($lbl5); $row += 20
    $tbNotes = New-Object System.Windows.Forms.TextBox
    $tbNotes.Location = New-Object System.Drawing.Point(14, $row); $tbNotes.Size = New-Object System.Drawing.Size(490, 22)
    if ($Existing) { $tbNotes.Text = $Existing.Notes }
    $d.Controls.Add($tbNotes); $row += 32

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = 'Save'; $btnOK.Location = New-Object System.Drawing.Point(330, 282); $btnOK.Size = New-Object System.Drawing.Size(80, 28)
    $btnOK.BackColor = [System.Drawing.Color]::FromArgb(39, 174, 96); $btnOK.ForeColor = [System.Drawing.Color]::White
    $script:editResult = $null
    $btnOK.Add_Click({
        if (-not $tbName.Text -or -not $tbUser.Text) {
            [System.Windows.Forms.MessageBox]::Show('Name and Username are required.', 'Save', 'OK', 'Warning') | Out-Null; return
        }
        if (-not $Existing -and -not $tbPwd.Text) {
            [System.Windows.Forms.MessageBox]::Show('Password is required for a new profile.', 'Save', 'OK', 'Warning') | Out-Null; return
        }
        # If editing and password left as <unchanged>, preserve existing password.
        if ($Existing -and $tbPwd.Text -eq '<unchanged>') {
            $cred = Get-AGCredentialAsPSCredential -Name $Existing.Name
        } else {
            $sec = ConvertTo-SecureString $tbPwd.Text -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ($tbUser.Text, $sec)
        }
        $script:editResult = @{
            Name       = $tbName.Text.Trim()
            Credential = $cred
            Type       = "$($cbType.SelectedItem)"
            Notes      = $tbNotes.Text
        }
        $d.DialogResult = 'OK'; $d.Close()
    })
    $d.Controls.Add($btnOK)
    $btnCancelC = New-Object System.Windows.Forms.Button
    $btnCancelC.Text = 'Cancel'; $btnCancelC.Location = New-Object System.Drawing.Point(420, 282); $btnCancelC.Size = New-Object System.Drawing.Size(80, 28)
    $btnCancelC.Add_Click({ $d.DialogResult = 'Cancel'; $d.Close() })
    $d.Controls.Add($btnCancelC)

    [void]$d.ShowDialog($form)
    return $script:editResult
}


function Global:Show-AuditAccountRequestDialog {
    [CmdletBinding()]
    param([string]$RootPath = $root)

    # Per-platform email templates. The operator picks ONE platform from
    # the dropdown and the dialog populates the corresponding subject +
    # body. Each platform owner gets a focused ask scoped to ONLY their
    # platform - no cross-platform identity, no over-broad permissions.
    $platformTemplates = [ordered]@{
        'AD / DNS / DHCP' = @{
            Subject = 'Request: Read-only AD/DNS/DHCP service account for AuthorityGate HealthCheck audit'
            Body = "Hello AD / DNS / DHCP Team,`r`n`r`nPlease create a dedicated read-only service account for the AuthorityGate HealthCheck audit. This account is scoped to AD / DNS / DHCP reads only - it does NOT touch vCenter, Horizon, or any other platform (those teams are receiving their own separate provisioning requests).`r`n`r`nWHAT WE NEED`r`n============`r`nActive Directory user:`r`n  sAMAccountName:     svc_audit_ad`r`n  DisplayName:        AuthorityGate AD Audit (Read-Only)`r`n  Description:        AuthorityGate HealthCheck read-only audit. Disable on <engagement-end-date>.`r`n  OU:                 your standard service-account OU (NOT CN=Users, NOT a privileged-tier OU)`r`n  Lockout threshold:  0 (do not lock out the audit run)`r`n`r`nGroup memberships (the entire AD footprint - no other groups):`r`n  - Domain Users     (default)`r`n  - DnsAdmins        (required for Get-DnsServer* RPC reads)`r`n  - DHCP Users       (READ-ONLY DHCP - NOT 'DHCP Administrators')`r`n`r`nOne ACL grant (read on Fine-Grained Password Policies):`r`n  dsacls `"CN=Password Settings Container,CN=System,<your-domain-dn>`" /G `"DOMAIN\svc_audit_ad:GR;;`"`r`n`r`nNO Domain Admin. NO Enterprise Admin. NO Server Operator. NO Local Admin anywhere.`r`n`r`nWHAT WE READ`r`n============`r`n- AD: privileged group membership, KRBTGT password age, stale computer accounts,`r`n  Default + Fine-Grained password policies, LAPS deployment, forest / domain`r`n  functional levels, FSMO holders, replication state, sites + subnets, trusts.`r`n- DNS: server settings, primary + reverse zones, conditional forwarders,`r`n  recursion + root hints, stale-record audit.`r`n- DHCP: server inventory, scopes, leases, reservations, failover state,`r`n  audit log + database health, scope options.`r`n`r`nNETWORK FROM AUDITOR HOST`r`n=========================`r`n- TCP/135 (RPC) to each DC, DNS server, DHCP server`r`n- TCP/53 (UDP+TCP) to DNS resolvers`r`n- Dynamic high ports (RPC return)`r`n`r`nREFERENCE`r`n=========`r`nFull setup recipe: https://github.com/AuthorityGate/Healthcheck/blob/main/docs/Audit-Account-Setup.md (Account 1)`r`n`r`nSend the password via your normal secrets channel after provisioning. Reply to architect@authoritygate.com with questions.`r`n`r`nThank you."
        }
        'vCenter' = @{
            Subject = 'Request: Read-only vCenter audit account for AuthorityGate HealthCheck'
            Body = "Hello vCenter Team,`r`n`r`nPlease create a dedicated read-only audit account on vCenter for the AuthorityGate HealthCheck. This account is scoped to vCenter only - other platforms receive separate provisioning requests.`r`n`r`nWHAT WE NEED`r`n============`r`nIdentity:`r`n  Either a vCenter SSO local user (svc_audit_vcenter@vsphere.local)`r`n  OR an AD user resolvable through your SSO Identity Source.`r`n`r`nRole binding:`r`n  Role:        Read-only (built-in)`r`n  Scope:       vCenter root (Administration -> Access Control -> Global Permissions)`r`n  Propagate:   yes, to all child entities`r`n`r`nSuggested username: svc_audit_vcenter`r`n`r`nWHAT WE READ`r`n============`r`n- Cluster + host + VM + datastore + network inventory`r`n- Performance metrics for the 30-day rollup peak plugins`r`n- Snapshot trees, hardware versions, VMTools status`r`n- Active alarms, recent failed tasks`r`n- vCenter license inventory, ESXi build / patch state`r`n- Per-host advanced settings (Hardening Guide audit)`r`n`r`nNETWORK FROM AUDITOR HOST`r`n=========================`r`n- TCP/443 (HTTPS) to vCenter`r`n`r`nREFERENCE`r`n=========`r`nFull setup recipe: https://github.com/AuthorityGate/Healthcheck/blob/main/docs/Audit-Account-Setup.md (Account 2)`r`n`r`nSend the password via your normal secrets channel. Reply to architect@authoritygate.com with questions.`r`n`r`nThank you."
        }
        'Horizon' = @{
            Subject = 'Request: Read-only Horizon audit account for AuthorityGate HealthCheck'
            Body = "Hello Horizon Team,`r`n`r`nPlease create a dedicated read-only audit account on the Horizon Connection Server for the AuthorityGate HealthCheck. This account is scoped to Horizon only.`r`n`r`nWHAT WE NEED`r`n============`r`nIdentity:`r`n  AD user, suggested sAMAccountName: svc_audit_horizon`r`n  Place in your standard service-account OU.`r`n`r`nHorizon role binding:`r`n  Horizon Console -> Settings -> Administrators -> Add User or Group`r`n    Role:                      Administrators (Read only)`r`n    Access group:              Root`r`n    Apply to subaccess groups: yes`r`n`r`nNO 2FA on this account (Horizon REST /login does not support MFA challenge).`r`n`r`nWHAT WE READ`r`n============`r`n- Connection Servers, gateways, pods, sites, federation`r`n- Pools, farms, machines, sessions, events`r`n- Authentication providers (RADIUS / SAML / TrueSSO / certs)`r`n- Network ranges, access groups, restricted tags`r`n- Helpdesk sessions (if Helpdesk plug-in is licensed)`r`n`r`nNETWORK FROM AUDITOR HOST`r`n=========================`r`n- TCP/443 to each Connection Server FQDN`r`n`r`nREFERENCE`r`n=========`r`nFull setup recipe: https://github.com/AuthorityGate/Healthcheck/blob/main/docs/Audit-Account-Setup.md (Account 3)`r`n`r`nThank you."
        }
        'App Volumes' = @{
            Subject = 'Request: Read-only App Volumes audit account for AuthorityGate HealthCheck'
            Body = "Hello App Volumes Team,`r`n`r`nPlease create a dedicated read-only audit account on App Volumes Manager for the AuthorityGate HealthCheck. Scoped to App Volumes only.`r`n`r`nWHAT WE NEED`r`n============`r`nIdentity:`r`n  Local AppVol Manager user OR an AD user (if AppVol AD-federated).`r`n  Suggested username: svc_audit_appvol`r`n`r`nAppVol role binding:`r`n  AppVol Manager -> Configuration -> Administrators -> Add`r`n    Role:    Auditors (the read-only built-in role)`r`n`r`nWHAT WE READ`r`n============`r`n- App package inventory + sync status, assignment + attachment tables`r`n- Storage groups + datastores + capacity`r`n- Writable volumes + capacity saturation`r`n- Active directory bindings, online sessions`r`n- Activity log (recent errors), admin audit log (last 7d)`r`n`r`nNETWORK FROM AUDITOR HOST`r`n=========================`r`n- TCP/443 to App Volumes Manager`r`n`r`nREFERENCE`r`n=========`r`nFull setup recipe: https://github.com/AuthorityGate/Healthcheck/blob/main/docs/Audit-Account-Setup.md (Account 4)`r`n`r`nThank you."
        }
        'Nutanix Prism' = @{
            Subject = 'Request: Read-only Nutanix Prism audit account for AuthorityGate HealthCheck'
            Body = "Hello Nutanix Team,`r`n`r`nPlease create a dedicated read-only audit account on Prism Central / Element for the AuthorityGate HealthCheck. Scoped to Nutanix only.`r`n`r`nIMPORTANT - MINIMUM-SCOPE ROLE`r`n==============================`r`nNutanix Prism exposes 390+ 'view_*' permissions. We are deliberately requesting only the 12 read-only permissions this audit actually queries (NOT a blanket 'Prism Admin' role).`r`n`r`nWHAT WE NEED`r`n============`r`n1. Custom role: AuthorityGate-HealthCheck-ReadOnly`r`n   The 12 permissions:`r`n     view_cluster, view_host, view_vm, view_storage_container, view_subnet,`r`n     view_vm_snapshot, view_alert, view_audit, view_task,`r`n     view_protection_rule, view_recovery_plan, view_lcm_entities`r`n   Or import the JSON: https://github.com/AuthorityGate/Healthcheck/blob/main/docs/Nutanix-ReadOnly-Role.json`r`n`r`n2. Service account (local Prism user OR AD-federated):`r`n   Suggested username: svc_audit_nutanix`r`n`r`n3. Bind the role at scope: All clusters (NOT a specific Project)`r`n`r`n4. Network: TCP/9440 reachable from auditor host`r`n`r`nWHAT WE READ`r`n============`r`n- Cluster + host + VM + storage container + subnet inventory`r`n- 30-day performance rollups for hosts and storage containers`r`n- Alerts (24h), audit (7d), failed tasks (24h)`r`n- DR posture (protection rules + recovery plans)`r`n- LCM firmware currency`r`n- Cluster headroom (N+1) modeling`r`n`r`nREFERENCE`r`n=========`r`nFull setup recipe: https://github.com/AuthorityGate/Healthcheck/blob/main/docs/Audit-Account-Setup.md (Account 5)`r`n`r`nThank you."
        }
        'Veeam' = @{
            Subject = 'Request: Read-only Veeam audit account for AuthorityGate HealthCheck'
            Body = "Hello Backup / DR Team,`r`n`r`nPlease create a dedicated read-only audit account on the Veeam Backup & Replication server for the AuthorityGate HealthCheck. Scoped to Veeam only.`r`n`r`nWHAT WE NEED`r`n============`r`nIdentity:`r`n  Local Veeam user OR an AD user.`r`n  Suggested username: svc_audit_veeam`r`n`r`nVeeam role binding:`r`n  Veeam Console -> Users and Roles -> Add`r`n    Role: Veeam Backup Viewer (read-only built-in)`r`n`r`nWHAT WE READ`r`n============`r`n- Backup job inventory + last-run results + age`r`n- Repository capacity + states`r`n- Per-VM protected status, recent restore points`r`n- Veeam license + edition + expiry`r`n`r`nNETWORK FROM AUDITOR HOST`r`n=========================`r`n- TCP/9419 (Veeam REST API) to VBR server`r`n`r`nREFERENCE`r`n=========`r`nFull setup recipe: https://github.com/AuthorityGate/Healthcheck/blob/main/docs/Audit-Account-Setup.md (Account 6)`r`n`r`nThank you."
        }
        'UAG' = @{
            Subject = 'Request: UAG admin password for AuthorityGate HealthCheck audit'
            Body = "Hello UAG / Edge Team,`r`n`r`nFor the AuthorityGate HealthCheck audit we need read access to each Unified Access Gateway's admin REST API. UAG admin is appliance-local by design - it cannot be AD-federated, so there is no separate audit account to create.`r`n`r`nWHAT WE NEED`r`n============`r`nFor each UAG appliance:`r`n  - The existing 'admin' user password OR a temporary password rotation for the audit`r`n  - One value per appliance if the customer's UAGs have different passwords`r`n`r`nWHAT WE READ`r`n============`r`n- System settings, edge service settings (View, Tunnel, Web Reverse Proxy, Content Gateway)`r`n- Auth methods (SAML / RADIUS / Cert / RSA / OAuth)`r`n- Network configuration (NICs, routes, DNS, NTP)`r`n- Live monitor stats (CPU / Mem / Disk / sessions)`r`n`r`nNETWORK FROM AUDITOR HOST`r`n=========================`r`n- TCP/9443 (UAG admin) to each UAG appliance`r`n`r`nREFERENCE`r`n=========`r`nFull setup recipe: https://github.com/AuthorityGate/Healthcheck/blob/main/docs/Audit-Account-Setup.md (Account 7)`r`n`r`nSend the password(s) via your normal secrets channel.`r`n`r`nThank you."
        }
        'Workspace ONE Access (vIDM)' = @{
            Subject = 'Request: vIDM OAuth client (Admin Read) for AuthorityGate HealthCheck audit'
            Body = "Hello Workspace ONE Access Team,`r`n`r`nThe vIDM REST API uses OAuth client_credentials grant rather than a user / password. For the AuthorityGate HealthCheck audit, please create a dedicated OAuth client with Admin Read scope.`r`n`r`nWHAT WE NEED`r`n============`r`nvIDM Console -> Catalog -> Settings -> Remote App Access -> Create Client`r`n  Access Type:      Service Client Token`r`n  Client ID:        audit-vidm-client (or any name you prefer)`r`n  Scope:            Admin Read`r`n  Token Type:       Bearer`r`n  Token TTL:        1 hour (default is fine)`r`n`r`nAfter clicking 'Generate Shared Secret', send the Client ID + Shared Secret via your normal secrets channel.`r`n`r`nNO user account is required - the OAuth client is a standalone identity.`r`n`r`nWHAT WE READ`r`n============`r`n- Tenant version + health, connector inventory, directory bindings`r`n- Application catalog, access policies, auth methods`r`n- Recent events (last 24h)`r`n`r`nNETWORK FROM AUDITOR HOST`r`n=========================`r`n- TCP/443 to vIDM tenant FQDN`r`n`r`nREFERENCE`r`n=========`r`nFull setup recipe: https://github.com/AuthorityGate/Healthcheck/blob/main/docs/Audit-Account-Setup.md (Account 8)`r`n`r`nThank you."
        }
        'Workspace ONE UEM' = @{
            Subject = 'Request: Read-only UEM admin + Tenant API key for AuthorityGate HealthCheck audit'
            Body = "Hello Workspace ONE UEM Team,`r`n`r`nThe UEM REST API needs both an admin user AND the tenant API key for header authentication. Please provision both for the AuthorityGate HealthCheck audit.`r`n`r`nWHAT WE NEED`r`n============`r`n1. UEM admin user (Read Only Admin role):`r`n   UEM Console -> Accounts -> Administrators -> Add Admin`r`n     Suggested username: svc_audit_uem`r`n     Role:               Read Only Admin`r`n   If UEM is AD-federated, an existing AD user can receive the role assignment.`r`n`r`n2. Tenant API key (the 'aw-tenant-code' header):`r`n   UEM Console -> All Settings -> System -> Advanced -> API -> REST API`r`n   Copy the API key for the Organization Group you want audited.`r`n`r`nSend both via your normal secrets channel.`r`n`r`nWHAT WE READ`r`n============`r`n- Device inventory + per-OG hierarchy`r`n- Smart groups, MDM profiles, managed apps (internal / public / purchased)`r`n- Compliance policies + state`r`n- Recent enrollments`r`n`r`nNETWORK FROM AUDITOR HOST`r`n=========================`r`n- TCP/443 to UEM Console FQDN`r`n`r`nREFERENCE`r`n=========`r`nFull setup recipe: https://github.com/AuthorityGate/Healthcheck/blob/main/docs/Audit-Account-Setup.md (Account 9)`r`n`r`nThank you."
        }
        'SQL Server (backing DBs)' = @{
            Subject = 'Request: SQL db_datareader account on Horizon / AppVol / vCenter backing DBs'
            Body = "Hello DBA Team,`r`n`r`nThe AuthorityGate HealthCheck audits SQL backing databases for Horizon, App Volumes, and (where present) the legacy vCenter database. We need read access ONLY - no schema, no sysadmin, no permissions outside the specific databases listed.`r`n`r`nWHAT WE NEED`r`n============`r`nSQL login (AD-auth preferred, SQL-auth acceptable):`r`n  Login name:    DOMAIN\svc_audit_sql (or SQL login if AD not viable)`r`n`r`nUser mapping per backing database:`r`n  Horizon Event DB:        db_datareader`r`n  App Volumes DB:          db_datareader`r`n  vCenter DB (if legacy):  db_datareader`r`n`r`nNOT sysadmin. NOT db_owner. NOT a server-level role beyond 'public'.`r`n`r`nWHAT WE READ`r`n============`r`n- DB state, data + log size, free space, recovery model`r`n- Last successful full backup timestamp + age (msdb.dbo.backupset)`r`n`r`nNETWORK FROM AUDITOR HOST`r`n=========================`r`n- TCP/1433 (or named-instance dynamic port) to each SQL Server`r`n`r`nREFERENCE`r`n=========`r`nFull setup recipe: https://github.com/AuthorityGate/Healthcheck/blob/main/docs/Audit-Account-Setup.md (Account 10)`r`n`r`nThank you."
        }
    }
    $defaultPlatform = 'AD / DNS / DHCP'

    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Generate Per-Platform Audit Account Request Email'
    $d.Size = New-Object System.Drawing.Size(880, 720)
    $d.StartPosition = 'CenterParent'
    $d.FormBorderStyle = 'Sizable'
    $d.MaximizeBox = $true
    $d.MinimumSize = New-Object System.Drawing.Size(680, 540)
    $d.AutoScroll = $true
    $d.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $lblPlatform = New-Object System.Windows.Forms.Label
    $lblPlatform.Text = 'Platform (each gets its own dedicated account scoped to that platform only):'
    $lblPlatform.Location = New-Object System.Drawing.Point(14, 12); $lblPlatform.Size = New-Object System.Drawing.Size(620, 18)
    $d.Controls.Add($lblPlatform)
    $cbPlatform = New-Object System.Windows.Forms.ComboBox
    $cbPlatform.Location = New-Object System.Drawing.Point(14, 32); $cbPlatform.Size = New-Object System.Drawing.Size(360, 22)
    $cbPlatform.DropDownStyle = 'DropDownList'
    foreach ($k in $platformTemplates.Keys) { [void]$cbPlatform.Items.Add($k) }
    $cbPlatform.SelectedItem = $defaultPlatform
    $d.Controls.Add($cbPlatform)

    $lblTo = New-Object System.Windows.Forms.Label
    $lblTo.Text = 'To: (the email of THIS platform owner)'
    $lblTo.Location = New-Object System.Drawing.Point(14, 62); $lblTo.Size = New-Object System.Drawing.Size(380, 18)
    $d.Controls.Add($lblTo)
    $tbTo = New-Object System.Windows.Forms.TextBox
    $tbTo.Location = New-Object System.Drawing.Point(14, 82); $tbTo.Size = New-Object System.Drawing.Size(820, 22)
    $tbTo.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $d.Controls.Add($tbTo)

    $lblSubj = New-Object System.Windows.Forms.Label
    $lblSubj.Text = 'Subject:'
    $lblSubj.Location = New-Object System.Drawing.Point(14, 112); $lblSubj.Size = New-Object System.Drawing.Size(380, 18)
    $d.Controls.Add($lblSubj)
    $tbSubj = New-Object System.Windows.Forms.TextBox
    $tbSubj.Location = New-Object System.Drawing.Point(14, 132); $tbSubj.Size = New-Object System.Drawing.Size(820, 22)
    $tbSubj.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $d.Controls.Add($tbSubj)

    $lblBody = New-Object System.Windows.Forms.Label
    $lblBody.Text = 'Body (forwardable):'
    $lblBody.Location = New-Object System.Drawing.Point(14, 162); $lblBody.Size = New-Object System.Drawing.Size(420, 18)
    $d.Controls.Add($lblBody)
    $tbBody = New-Object System.Windows.Forms.TextBox
    $tbBody.Location = New-Object System.Drawing.Point(14, 182); $tbBody.Size = New-Object System.Drawing.Size(820, 438)
    $tbBody.Multiline = $true
    $tbBody.ScrollBars = 'Vertical'
    $tbBody.Font = New-Object System.Drawing.Font('Consolas', 8.5)
    $tbBody.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $d.Controls.Add($tbBody)

    $applyTemplate = {
        $sel = $cbPlatform.SelectedItem
        if ($sel -and $platformTemplates.Contains($sel)) {
            $tbSubj.Text = $platformTemplates[$sel].Subject
            $tbBody.Text = $platformTemplates[$sel].Body
        }
    }
    & $applyTemplate
    $cbPlatform.Add_SelectedIndexChanged($applyTemplate)

    $btnCopy = New-Object System.Windows.Forms.Button
    $btnCopy.Text = 'Copy to Clipboard'
    $btnCopy.Location = New-Object System.Drawing.Point(14, 632); $btnCopy.Size = New-Object System.Drawing.Size(160, 30)
    $btnCopy.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnCopy.Add_Click({
        try { [System.Windows.Forms.Clipboard]::SetText("Subject: $($tbSubj.Text)`r`n`r`n$($tbBody.Text)"); [System.Windows.Forms.MessageBox]::Show('Email copied to clipboard.', 'Copied', 'OK', 'Information') | Out-Null }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Error', 'OK', 'Error') | Out-Null }
    })
    $d.Controls.Add($btnCopy)

    $btnOutlook = New-Object System.Windows.Forms.Button
    $btnOutlook.Text = 'Open in Outlook'
    $btnOutlook.Location = New-Object System.Drawing.Point(184, 632); $btnOutlook.Size = New-Object System.Drawing.Size(160, 30)
    $btnOutlook.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnOutlook.Add_Click({
        try {
            $outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
            $mail = $outlook.CreateItem(0)
            $mail.To = $tbTo.Text; $mail.Subject = $tbSubj.Text; $mail.Body = $tbBody.Text
            $mail.Display() | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Outlook COM not available. Use Copy to Clipboard or Save as .txt instead.", 'Outlook unavailable', 'OK', 'Information') | Out-Null
        }
    })
    $d.Controls.Add($btnOutlook)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Save as .txt...'
    $btnSave.Location = New-Object System.Drawing.Point(354, 632); $btnSave.Size = New-Object System.Drawing.Size(140, 30)
    $btnSave.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnSave.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = 'Text file (*.txt)|*.txt|All files|*.*'
        $sfd.FileName = "Audit-Account-Request-$(($cbPlatform.SelectedItem -replace '[^a-zA-Z0-9]+','-')).txt"
        if ($sfd.ShowDialog() -eq 'OK') {
            try { Set-Content -Path $sfd.FileName -Value ("Subject: $($tbSubj.Text)`r`n`r`n$($tbBody.Text)") -Encoding UTF8 } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Save error', 'OK', 'Error') | Out-Null }
        }
    })
    $d.Controls.Add($btnSave)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Location = New-Object System.Drawing.Point(764, 632); $btnClose.Size = New-Object System.Drawing.Size(80, 30)
    $btnClose.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnClose.Add_Click({ $d.Close() })
    $d.Controls.Add($btnClose)

    [void]$d.ShowDialog()
}


function Global:Show-NutanixAccessRequestDialog {
    [CmdletBinding()]
    param(
        [string]$RootPath = $root,
        [string]$PrismFqdn = '',
        [string]$ServiceAccountUser = ''
    )
    # Compose a forwardable email body that the customer can paste into
    # Outlook OR forward through their procurement / change-control queue.
    # Body includes: the ask, the why, the exact permissions, the role JSON
    # (inline so a Nutanix admin can import without us shipping a separate
    # attachment), and a short Q&A pointer.
    $rolePath = Join-Path $RootPath 'docs\Nutanix-ReadOnly-Role.json'
    $roleJson = ''
    if (Test-Path $rolePath) {
        try { $roleJson = (Get-Content -Raw -Path $rolePath -ErrorAction Stop) } catch { $roleJson = '(role JSON file missing - copy from https://github.com/AuthorityGate/Healthcheck/blob/main/docs/Nutanix-ReadOnly-Role.json)' }
    } else {
        $roleJson = '(role JSON file missing - copy from https://github.com/AuthorityGate/Healthcheck/blob/main/docs/Nutanix-ReadOnly-Role.json)'
    }
    $envHint = if ($PrismFqdn) { $PrismFqdn } else { '<your-Prism-Central-or-Element-FQDN>' }
    $usernameHint = if ($ServiceAccountUser) { $ServiceAccountUser } else { 'svc_authoritygate_audit' }

    $subject = "Request: Read-only Nutanix Prism service account for AuthorityGate HealthCheck audit"
    $body = @"
Hello Nutanix Administrator,

Please create a read-only service account on Prism Central / Element ($envHint) for the upcoming AuthorityGate HealthCheck audit. This account is needed only for inventory + capacity + alert collection - NO write or mutating permissions are required or used.

WHAT WE NEED
============
1. A custom role with the 11 read-only permissions listed below.

   IMPORTANT: Nutanix Prism exposes 390+ "view_*" permissions across the
   v3 surface area; we are DELIBERATELY requesting only the minimum-scope
   subset (11 permissions) that this audit actually queries. This keeps
   your least-privilege posture intact - the role does not grant access
   to encryption keys, IDP secrets, license tokens, Calm blueprints,
   Files / Objects, Move, Era, or anything beyond the 11 listed below.

   Suggested role name: AuthorityGate-HealthCheck-ReadOnly

   Import via Prism: Administration -> Roles -> Create Role and tick the
   11 permissions below, OR POST the JSON spec at the bottom of this
   email to /api/nutanix/v3/roles.

2. A service account (local Prism user OR domain user via your existing IDP):
   Suggested username: $usernameHint
   Strong password (we'll prompt the runner; nothing is stored locally)

3. Bind the role to the account at scope "All clusters" (NOT a specific Project) so the auditor can see the full estate.

4. Network: TCP/9440 reachable from the auditor's runner machine to $envHint.

PERMISSIONS REQUIRED (11 read-only operations - the entire ask)
===============================================================
- view_cluster              (cluster inventory, RF posture, AOS version)
- view_host                 (per-host hardware, CPU/RAM, 30-day perf peak)
- view_vm                   (VM state summary)
- view_storage_container    (capacity + 30-day fill peak)
- view_subnet               (AHV network inventory + VLAN audit)
- view_vm_snapshot          (snapshot sprawl + age)
- view_alert                (active alerts last 24h)
- view_audit                (admin actions last 7d)
- view_task                 (failed tasks last 24h)
- view_protection_rule      (DR / replication policy inventory)
- view_recovery_plan        (DR runbook inventory)

WHAT WE WILL DO WITH THE ACCESS
===============================
Read inventory and 30-day performance rollups via the v3 REST API at
https://$envHint:9440/api/nutanix/v3/. Output is rendered locally as an
HTML report. No data is exported to any third party. Source code is at
https://github.com/AuthorityGate/Healthcheck.

CUSTOM ROLE JSON (import via Prism)
===================================
$roleJson

QUESTIONS
=========
Reply to architect@authoritygate.com or open an issue at the GitHub repo
above. Once the account is created, please send the username + password
via your normal secrets channel.

Thank you.
"@

    # Build the dialog
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Generate Nutanix Access Request Email'
    $d.Size = New-Object System.Drawing.Size(820, 640)
    $d.StartPosition = 'CenterParent'
    $d.FormBorderStyle = 'Sizable'
    $d.MaximizeBox = $true
    $d.MinimumSize = New-Object System.Drawing.Size(640, 460)
    $d.AutoScroll = $true
    $d.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $lblTo = New-Object System.Windows.Forms.Label
    $lblTo.Text = 'To: (your Nutanix admin team email)'
    $lblTo.Location = New-Object System.Drawing.Point(14, 12); $lblTo.Size = New-Object System.Drawing.Size(280, 18)
    $d.Controls.Add($lblTo)
    $tbTo = New-Object System.Windows.Forms.TextBox
    $tbTo.Location = New-Object System.Drawing.Point(14, 32); $tbTo.Size = New-Object System.Drawing.Size(770, 22)
    $tbTo.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $d.Controls.Add($tbTo)

    $lblSubj = New-Object System.Windows.Forms.Label
    $lblSubj.Text = 'Subject:'
    $lblSubj.Location = New-Object System.Drawing.Point(14, 62); $lblSubj.Size = New-Object System.Drawing.Size(280, 18)
    $d.Controls.Add($lblSubj)
    $tbSubj = New-Object System.Windows.Forms.TextBox
    $tbSubj.Location = New-Object System.Drawing.Point(14, 82); $tbSubj.Size = New-Object System.Drawing.Size(770, 22)
    $tbSubj.Text = $subject
    $tbSubj.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $d.Controls.Add($tbSubj)

    $lblBody = New-Object System.Windows.Forms.Label
    $lblBody.Text = 'Body (forwardable - edit before sending if you want):'
    $lblBody.Location = New-Object System.Drawing.Point(14, 112); $lblBody.Size = New-Object System.Drawing.Size(500, 18)
    $d.Controls.Add($lblBody)
    $tbBody = New-Object System.Windows.Forms.TextBox
    $tbBody.Location = New-Object System.Drawing.Point(14, 132); $tbBody.Size = New-Object System.Drawing.Size(770, 410)
    $tbBody.Multiline = $true
    $tbBody.ScrollBars = 'Vertical'
    $tbBody.Font = New-Object System.Drawing.Font('Consolas', 8.5)
    $tbBody.Text = $body
    $tbBody.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $d.Controls.Add($tbBody)

    # Buttons row
    $btnCopy = New-Object System.Windows.Forms.Button
    $btnCopy.Text = 'Copy to Clipboard'
    $btnCopy.Location = New-Object System.Drawing.Point(14, 555); $btnCopy.Size = New-Object System.Drawing.Size(160, 30)
    $btnCopy.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnCopy.Add_Click({
        $clip = "Subject: $($tbSubj.Text)`r`n`r`n$($tbBody.Text)"
        try { [System.Windows.Forms.Clipboard]::SetText($clip); [System.Windows.Forms.MessageBox]::Show('Email copied to clipboard. Paste into your mail client.', 'Copied', 'OK', 'Information') | Out-Null }
        catch { [System.Windows.Forms.MessageBox]::Show("Clipboard copy failed: $($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null }
    })
    $d.Controls.Add($btnCopy)

    $btnOutlook = New-Object System.Windows.Forms.Button
    $btnOutlook.Text = 'Open in Outlook'
    $btnOutlook.Location = New-Object System.Drawing.Point(184, 555); $btnOutlook.Size = New-Object System.Drawing.Size(160, 30)
    $btnOutlook.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnOutlook.Add_Click({
        # Try Outlook COM first (works on every Windows machine with Outlook
        # installed). Falls back to mailto: which most browsers/MAPI clients
        # honor but is limited to ~2KB of body length.
        try {
            $outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
            $mail = $outlook.CreateItem(0)
            $mail.To = $tbTo.Text
            $mail.Subject = $tbSubj.Text
            $mail.Body = $tbBody.Text
            $mail.Display() | Out-Null
        } catch {
            try {
                $encSubj = [System.Net.WebUtility]::UrlEncode($tbSubj.Text)
                $encBody = [System.Net.WebUtility]::UrlEncode($tbBody.Text)
                $url = "mailto:$($tbTo.Text)?subject=$encSubj&body=$encBody"
                if ($url.Length -gt 1900) {
                    [System.Windows.Forms.MessageBox]::Show('Email body is too long for the OS mailto: handler. Use "Copy to Clipboard" or "Save as .txt" instead.', 'Body too long', 'OK', 'Warning') | Out-Null
                    return
                }
                Start-Process $url
            } catch { [System.Windows.Forms.MessageBox]::Show("Could not open mail client: $($_.Exception.Message). Use Copy to Clipboard instead.", 'Error', 'OK', 'Error') | Out-Null }
        }
    })
    $d.Controls.Add($btnOutlook)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Save as .txt...'
    $btnSave.Location = New-Object System.Drawing.Point(354, 555); $btnSave.Size = New-Object System.Drawing.Size(140, 30)
    $btnSave.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnSave.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = 'Text file (*.txt)|*.txt|All files|*.*'
        $sfd.FileName = 'Nutanix-Access-Request.txt'
        if ($sfd.ShowDialog() -eq 'OK') {
            try { Set-Content -Path $sfd.FileName -Value ("Subject: $($tbSubj.Text)`r`n`r`n$($tbBody.Text)") -Encoding UTF8 } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Save error', 'OK', 'Error') | Out-Null }
        }
    })
    $d.Controls.Add($btnSave)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Location = New-Object System.Drawing.Point(704, 555); $btnClose.Size = New-Object System.Drawing.Size(80, 30)
    $btnClose.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnClose.Add_Click({ $d.Close() })
    $d.Controls.Add($btnClose)

    [void]$d.ShowDialog()
}

$btnGold = New-Object System.Windows.Forms.Button
$btnGold.Text = 'Pick Gold Images...'
$btnGold.Location = New-Object System.Drawing.Point(238, 732)
$btnGold.Size     = New-Object System.Drawing.Size(170, 28)
$btnGold.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$btnGold.FlatStyle = 'Flat'
$btnGold.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnGold.Add_Click({
    # Allow Nutanix-only mode: at least one hypervisor backend must be filled.
    $hasVC   = ($cVC.Server.Text -and $cVC.User.Text -and $cVC.Pass.Text)
    $hasNTNX = ($cNTNX -and $cNTNX.Server.Text -and $cNTNX.User.Text -and $cNTNX.Pass.Text)
    if (-not $hasVC -and -not $hasNTNX) {
        [System.Windows.Forms.MessageBox]::Show('Fill in vCenter Server (FQDN+User+Pass) OR Nutanix Prism (FQDN+User+Pass) on the relevant tab first. The picker connects on-demand to enumerate VMs from whichever hypervisor(s) you provide.', 'Pick Gold Images', 'OK', 'Information') | Out-Null
        return
    }
    Show-GoldImagePicker
})
$form.Controls.Add($btnGold)

# Generate Audit Account Request Email - emits a forwardable email to the
# customer's identity / platform team asking for the single AD service
# account + role bindings the audit needs.
$btnAcctReq = New-Object System.Windows.Forms.Button
$btnAcctReq.Text = 'Generate Per-Platform Account Request...'
$btnAcctReq.Location = New-Object System.Drawing.Point(594, 732)
$btnAcctReq.Size     = New-Object System.Drawing.Size(220, 28)
$btnAcctReq.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$btnAcctReq.FlatStyle = 'Flat'
$btnAcctReq.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnAcctReq.Add_Click({ Show-AuditAccountRequestDialog -RootPath $root })
$form.Controls.Add($btnAcctReq)

# Single combined help label on a row beneath all the action buttons.
# Height of 36 px accommodates the natural text wrap at the default 870 px
# width - text is too long for one line, and clipping it to one row caused
# the second wrapped line to draw on top of the log frame below.
$lblRow2 = New-Object System.Windows.Forms.Label
$lblRow2.Text = 'Specialized = AD/MFA/Imprivata/DEM/AV-pkg/customer  |  Pick Gold Images = browse vCenter + select masters  |  Manage Credentials = save reusable named profiles  |  Account Request = generate per-platform email'
$lblRow2.Location = New-Object System.Drawing.Point(12, 764)
$lblRow2.Size     = New-Object System.Drawing.Size(870, 36)
$lblRow2.ForeColor = [System.Drawing.Color]::FromArgb(96, 96, 96)
$lblRow2.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$lblRow2.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor `
                  [System.Windows.Forms.AnchorStyles]::Left   -bor `
                  [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($lblRow2)

function Global:Show-GoldImagePicker {
    # Dedicated VC session for the picker - so we do not interfere with the
    # main run. Disconnected on dialog close.
    $dlgGold = New-Object System.Windows.Forms.Form
    $dlgGold.Text = 'Pick Gold Images'
    $dlgGold.Size = New-Object System.Drawing.Size(1100, 720)
    $dlgGold.StartPosition = 'CenterParent'
    $dlgGold.FormBorderStyle = 'Sizable'
    $dlgGold.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Location = New-Object System.Drawing.Point(14, 12)
    $lblStatus.Size     = New-Object System.Drawing.Size(870, 20)
    $lblStatus.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $lblStatus.Text     = 'Connecting to vCenter ...'
    $dlgGold.Controls.Add($lblStatus)

    # Live search box - filters the VM list as the operator types. Case-
    # insensitive substring match against name, cluster, OS, power, tools.
    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text = 'Search (name / cluster / OS):'
    $lblSearch.Location = New-Object System.Drawing.Point(14, 40)
    $lblSearch.Size     = New-Object System.Drawing.Size(180, 20)
    $dlgGold.Controls.Add($lblSearch)

    $tbSearch = New-Object System.Windows.Forms.TextBox
    $tbSearch.Location = New-Object System.Drawing.Point(196, 38)
    $tbSearch.Size     = New-Object System.Drawing.Size(540, 22)
    $tbSearch.Anchor   = 'Top,Left,Right'
    $dlgGold.Controls.Add($tbSearch)

    $lblMatch = New-Object System.Windows.Forms.Label
    $lblMatch.Text = ''
    $lblMatch.Location = New-Object System.Drawing.Point(744, 40)
    $lblMatch.Size     = New-Object System.Drawing.Size(330, 20)
    $lblMatch.ForeColor = [System.Drawing.Color]::FromArgb(96, 96, 96)
    $lblMatch.Anchor   = 'Top,Right'
    $dlgGold.Controls.Add($lblMatch)

    # ListView of VMs with checkboxes
    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = New-Object System.Drawing.Point(14, 68)
    $lv.Size     = New-Object System.Drawing.Size(1060, 510)
    $lv.View     = 'Details'
    $lv.CheckBoxes = $true
    $lv.FullRowSelect = $true
    $lv.GridLines = $true
    $lv.Anchor = 'Top,Bottom,Left,Right'
    [void]$lv.Columns.Add('VM', 180)
    [void]$lv.Columns.Add('Source', 70)
    [void]$lv.Columns.Add('Cluster', 100)
    [void]$lv.Columns.Add('Power', 70)
    [void]$lv.Columns.Add('Tools', 70)
    [void]$lv.Columns.Add('Guest OS', 160)
    [void]$lv.Columns.Add('Snaps', 50)
    [void]$lv.Columns.Add('vCPU/RAM', 80)
    [void]$lv.Columns.Add('Cred Profile', 180)
    $dlgGold.Controls.Add($lv)

    # Action buttons
    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = 'Refresh'
    $btnRefresh.Location = New-Object System.Drawing.Point(14, 590)
    $btnRefresh.Size     = New-Object System.Drawing.Size(90, 28)
    $btnRefresh.Anchor = 'Bottom,Left'
    $dlgGold.Controls.Add($btnRefresh)

    $btnPowerOn = New-Object System.Windows.Forms.Button
    $btnPowerOn.Text = 'Power On Selected'
    $btnPowerOn.Location = New-Object System.Drawing.Point(100, 590)
    $btnPowerOn.Size     = New-Object System.Drawing.Size(130, 28)
    $btnPowerOn.Anchor = 'Bottom,Left'
    $dlgGold.Controls.Add($btnPowerOn)

    $btnTest = New-Object System.Windows.Forms.Button
    $btnTest.Text = 'Test Reachability'
    $btnTest.Location = New-Object System.Drawing.Point(236, 590)
    $btnTest.Size     = New-Object System.Drawing.Size(130, 28)
    $btnTest.Anchor = 'Bottom,Left'
    $dlgGold.Controls.Add($btnTest)

    $btnSetCred = New-Object System.Windows.Forms.Button
    $btnSetCred.Text = 'Set Cred Profile for Checked...'
    $btnSetCred.Location = New-Object System.Drawing.Point(372, 590)
    $btnSetCred.Size     = New-Object System.Drawing.Size(220, 28)
    $btnSetCred.Anchor = 'Bottom,Left'
    $dlgGold.Controls.Add($btnSetCred)

    $btnFilter = New-Object System.Windows.Forms.Button
    $btnFilter.Text = 'Filter: All VMs'
    $btnFilter.Location = New-Object System.Drawing.Point(598, 590)
    $btnFilter.Size     = New-Object System.Drawing.Size(140, 28)
    $btnFilter.Anchor = 'Bottom,Left'
    $dlgGold.Controls.Add($btnFilter)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Save Selected'
    $btnSave.Location = New-Object System.Drawing.Point(880, 590)
    $btnSave.Size     = New-Object System.Drawing.Size(110, 28)
    $btnSave.Anchor = 'Bottom,Right'
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(39, 174, 96); $btnSave.ForeColor = [System.Drawing.Color]::White
    $dlgGold.Controls.Add($btnSave)
    $btnCancelGold = New-Object System.Windows.Forms.Button
    $btnCancelGold.Text = 'Cancel'
    $btnCancelGold.Location = New-Object System.Drawing.Point(994, 590)
    $btnCancelGold.Size     = New-Object System.Drawing.Size(80, 28)
    $btnCancelGold.Anchor = 'Bottom,Right'
    $btnCancelGold.Add_Click({ $dlgGold.DialogResult = 'Cancel'; $dlgGold.Close() })
    $dlgGold.Controls.Add($btnCancelGold)

    $script:filterMode = 'all'
    # Cache: every VM that came back from vCenter on the last enumerate, with
    # its display columns pre-computed. The search textbox filters this cache
    # client-side so typing does NOT re-query vCenter on every keystroke.
    $script:gpRows = @()
    # Session-wide check state, keyed by VM name. Survives filter / search
    # changes (the ListView gets cleared+repopulated on every render, so we
    # cannot rely on per-item Checked state to persist across renders).
    # Seeded from the saved $Script:ManualGoldImages list so previous picks
    # are pre-checked on open.
    $script:gpChecked = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($n in @($Script:ManualGoldImages)) { if ($n) { [void]$script:gpChecked.Add($n) } }
    $script:gpRenderInProgress = $false

    # Render the current $script:gpRows into the ListView, optionally filtered
    # by $tbSearch.Text (case-insensitive substring match across name +
    # cluster + power + tools + OS columns). Initial check state for each
    # row comes from the session-wide $script:gpChecked set so picks survive
    # filter / search changes.
    $render = {
        $script:gpRenderInProgress = $true
        $lv.BeginUpdate()
        try {
            $lv.Items.Clear()
            $needle = if ($tbSearch -and $tbSearch.Text) { $tbSearch.Text.Trim().ToLowerInvariant() } else { '' }
            $shown = 0
            foreach ($r in $script:gpRows) {
                if ($needle) {
                    $hay = "$($r.Name) $($r.Cluster) $($r.Power) $($r.Tools) $($r.OS)".ToLowerInvariant()
                    if ($hay -notmatch [regex]::Escape($needle)) { continue }
                }
                $item = New-Object System.Windows.Forms.ListViewItem([string]$r.Name)
                [void]$item.SubItems.Add([string]$r.Cluster)
                [void]$item.SubItems.Add([string]$r.Power)
                [void]$item.SubItems.Add([string]$r.Tools)
                [void]$item.SubItems.Add([string]$r.OS)
                [void]$item.SubItems.Add([string]$r.Snaps)
                [void]$item.SubItems.Add([string]$r.Sizing)
                $existingCred = if ($Script:ManualGoldImageCreds -and $Script:ManualGoldImageCreds.ContainsKey($r.Name)) { $Script:ManualGoldImageCreds[$r.Name] } else { '' }
                [void]$item.SubItems.Add([string]$existingCred)
                if ($script:gpChecked.Contains($r.Name)) { $item.Checked = $true }
                if ($r.Power -eq 'PoweredOff') {
                    $item.ForeColor = [System.Drawing.Color]::FromArgb(180, 60, 30)
                }
                [void]$lv.Items.Add($item)
                $shown++
            }
            if ($needle) {
                $lblMatch.Text = "$shown of $($script:gpRows.Count) match  |  $($script:gpChecked.Count) checked"
            } else {
                $lblMatch.Text = "$($script:gpRows.Count) VMs  |  $($script:gpChecked.Count) checked"
            }
        } finally {
            $lv.EndUpdate()
            $script:gpRenderInProgress = $false
        }
    }

    # Track every check/uncheck so a row's state survives filter changes.
    # Skip events fired during $render (we set Checked programmatically there).
    $lv.Add_ItemChecked({
        param($s,$e)
        if ($script:gpRenderInProgress) { return }
        $name = $e.Item.Text
        if ($e.Item.Checked) {
            [void]$script:gpChecked.Add($name)
        } else {
            [void]$script:gpChecked.Remove($name)
        }
        # Update the counter without re-rendering (avoid recursion + flicker)
        $needle = if ($tbSearch -and $tbSearch.Text) { $tbSearch.Text.Trim().ToLowerInvariant() } else { '' }
        if ($needle) {
            $lblMatch.Text = "$($lv.Items.Count) of $($script:gpRows.Count) match  |  $($script:gpChecked.Count) checked"
        } else {
            $lblMatch.Text = "$($script:gpRows.Count) VMs  |  $($script:gpChecked.Count) checked"
        }
    })

    $populate = {
        $lblStatus.Text = 'Querying vCenter for VMs ...'
        $dlgGold.Refresh()
        try {
            $allVms = Get-VM -ErrorAction Stop
            # Apply filter
            $vms = switch ($script:filterMode) {
                'parents'    { $allVms | Where-Object { $_.Name -match 'parent|gold|master|tmpl|template|prep|capture|pkg' } }
                'powered-on' { $allVms | Where-Object { $_.PowerState -eq 'PoweredOn' } }
                default      { $allVms }
            }
            $rows = @()
            foreach ($vm in ($vms | Sort-Object Name)) {
                # PowerCLI returns enum/string mixes; force every subitem to a
                # plain [string] so ListViewSubItemCollection.Add picks the
                # correct overload. The enum 'Running' was tripping the cast.
                $cluster = if ($vm.VMHost -and $vm.VMHost.Parent) { [string]$vm.VMHost.Parent.Name } else { '' }
                $tools   = if ($vm.Guest  -and $vm.Guest.State)   { [string]$vm.Guest.State }      else { 'unknown' }
                $os      = if ($vm.Guest  -and $vm.Guest.OSFullName) { [string]$vm.Guest.OSFullName } else { '' }
                $snaps   = @(Get-Snapshot -VM $vm -ErrorAction SilentlyContinue).Count
                $sizing  = "$($vm.NumCpu)c / $([math]::Round($vm.MemoryGB,0))GB"
                $rows += [pscustomobject]@{
                    Name    = [string]$vm.Name
                    Cluster = $cluster
                    Power   = [string]$vm.PowerState
                    Tools   = $tools
                    OS      = $os
                    Snaps   = [string]$snaps
                    Sizing  = $sizing
                }
            }
            $script:gpRows = $rows
            $lblStatus.Text = "Loaded $($rows.Count) VMs (filter: $script:filterMode). Type in the search box above to narrow the list. Check VMs and Save."
            & $render
        } catch {
            $lblStatus.Text = "Failed to enumerate VMs: $($_.Exception.Message)"
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
        }
    }

    # Live filter: every keystroke re-renders from the cached row list.
    $tbSearch.Add_TextChanged({ & $render })

    # Connect to vCenter for the picker
    Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
    if ($cVC.SkipCert.Checked) { Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null }
    $secPw = ConvertTo-SecureString $cVC.Pass.Text -AsPlainText -Force
    $vcCred = New-Object System.Management.Automation.PSCredential ($cVC.User.Text, $secPw)
    $vcList = @($cVC.Server.Text -split '[,;]\s*' | Where-Object { $_.Trim() })
    $connected = @()
    foreach ($vcOne in $vcList) {
        try {
            Connect-VIServer -Server $vcOne -Credential $vcCred -ErrorAction Stop | Out-Null
            $connected += $vcOne
        } catch {
            $lblStatus.Text = "Connect failed for $vcOne : $($_.Exception.Message)"
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
        }
    }
    if ($connected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Could not connect to any vCenter from the list: $($vcList -join ', ')", 'Pick Gold Images', 'OK', 'Error') | Out-Null
        $dlgGold.Close()
        return
    }

    & $populate
    $btnRefresh.Add_Click({ & $populate })
    $btnFilter.Add_Click({
        $next = switch ($script:filterMode) { 'all' { 'parents' } 'parents' { 'powered-on' } default { 'all' } }
        $script:filterMode = $next
        $btnFilter.Text = "Filter: $next"
        & $populate
    })

    $btnPowerOn.Add_Click({
        $checked = @($lv.CheckedItems)
        $offCount = 0
        foreach ($it in $checked) {
            if ($it.SubItems[2].Text -eq 'PoweredOff') {
                $offCount++
                try {
                    Get-VM -Name $it.Text | Start-VM -Confirm:$false -ErrorAction Stop | Out-Null
                    $it.SubItems[2].Text = 'Starting...'
                    $it.ForeColor = [System.Drawing.Color]::FromArgb(0, 100, 0)
                } catch {
                    $it.SubItems[2].Text = "Err: $($_.Exception.Message)"
                }
            }
        }
        if ($offCount -gt 0) {
            [System.Windows.Forms.MessageBox]::Show("Power-on issued for $offCount VM(s). Click Refresh in ~60 seconds to verify Tools = Running.", 'Pick Gold Images', 'OK', 'Information') | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show('No checked VMs were in PoweredOff state.', 'Pick Gold Images', 'OK', 'Information') | Out-Null
        }
    })

    $btnTest.Add_Click({
        $checked = @($lv.CheckedItems)
        if ($checked.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('Check one or more VMs first.', 'Pick Gold Images', 'OK', 'Information') | Out-Null
            return
        }
        $lblStatus.Text = "Testing reachability for $($checked.Count) VM(s) ..."; $dlgGold.Refresh()
        foreach ($it in $checked) {
            try {
                # Guard: subitem must exist before we can write to it.
                if ($it.SubItems.Count -lt 4) {
                    while ($it.SubItems.Count -lt 8) { [void]$it.SubItems.Add('') }
                }
                $vmResult = @(Get-VM -Name $it.Text -ErrorAction SilentlyContinue)
                if ($vmResult.Count -eq 0) { $it.SubItems[3].Text = 'NotFound'; continue }
                # If multiple VMs match across vCenters, take the first.
                $vm = $vmResult[0]
                $tools = if ($vm.Guest -and $vm.Guest.State) { [string]$vm.Guest.State } else { 'unknown' }
                # Guest.IPAddress can be null, empty list, or a List<string>.
                # Wrap defensively and pick first non-empty entry.
                $ipList = @()
                if ($vm.Guest -and $vm.Guest.IPAddress) {
                    $ipList = @($vm.Guest.IPAddress | Where-Object { $_ -and ($_ -notmatch '^(169\.254|fe80:)') })
                }
                $ip = if ($ipList.Count -gt 0) { [string]$ipList[0] } else { '' }
                $tcp = $false
                if ($ip) {
                    try {
                        $t = New-Object System.Net.Sockets.TcpClient
                        $async = $t.BeginConnect($ip, 5985, $null, $null)
                        $tcp = $async.AsyncWaitHandle.WaitOne(1500, $false) -and $t.Connected
                        $t.Close()
                    } catch { }
                }
                $reachLabel = if ($ip) { "$tools / $ip / WinRM=$([string]$tcp)" } else { "$tools / no-IP" }
                $it.SubItems[3].Text = $reachLabel
            } catch {
                # Don't let one bad row abort the whole batch.
                try { $it.SubItems[3].Text = "Error: $($_.Exception.Message.Substring(0,[Math]::Min(40,$_.Exception.Message.Length)))" } catch { }
            }
        }
        $lblStatus.Text = 'Reachability test complete.'
    })

    $btnSetCred.Add_Click({
        try {
            $checked = @($lv.CheckedItems)
            if ($checked.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show('Check one or more VMs first, then click Set Cred Profile to assign a credential to those VMs.', 'Pick Gold Images', 'OK', 'Information') | Out-Null
                return
            }
            # Make sure the per-VM map exists before any closure writes to it.
            if (-not $Script:ManualGoldImageCreds) { $Script:ManualGoldImageCreds = @{} }
            # Defensively guarantee SubItems[7] exists for every checked row -
            # the ListView populator pads to 8 subitems, but a leftover row
            # from a stale enumeration could be short.
            foreach ($it in $checked) {
                while ($it.SubItems.Count -lt 8) { [void]$it.SubItems.Add('') }
            }
            # Capture parent-scope refs into locals so .GetNewClosure() can
            # snapshot them. Without this, the menu-item click handler runs
            # later in a scope where $lblStatus is not visible (dialog-builder
            # function locals don't propagate through nested closures), and
            # $lblStatus.Text throws "property 'Text' cannot be found".
            $lblStatusRef = $lblStatus
            $menu = New-Object System.Windows.Forms.ContextMenuStrip
            $profiles = @()
            try {
                $profiles = @(Get-AGCredentialProfile | Where-Object { $_ -and ($_.Type -in @('Local','Domain','Other')) } | Sort-Object Name)
            } catch {
                # Profile store may be uninitialized or corrupt - present an
                # empty list, the Manage Credentials entry stays usable.
                $profiles = @()
            }
            if ($profiles.Count -eq 0) {
                $miEmpty = $menu.Items.Add('(no profiles - click Manage Credentials below)')
                $miEmpty.Enabled = $false
            } else {
                foreach ($p in $profiles) {
                    $mi = $menu.Items.Add("$($p.Name)  -  $($p.UserName)  [$($p.Type)]")
                    $mi.Tag = $p.Name
                    $mi.Add_Click({
                        param($s,$e)
                        try {
                            if (-not $Script:ManualGoldImageCreds) { $Script:ManualGoldImageCreds = @{} }
                            $count = 0
                            foreach ($it in $checked) {
                                if (-not $it -or -not $it.Text) { continue }
                                $Script:ManualGoldImageCreds[$it.Text] = [string]$s.Tag
                                if ($it.SubItems -and $it.SubItems.Count -gt 7) { $it.SubItems[7].Text = [string]$s.Tag }
                                $count++
                            }
                            if ($lblStatusRef) { $lblStatusRef.Text = "Assigned profile '$($s.Tag)' to $count VM(s). Save Selected to commit." }
                        } catch {
                            [System.Windows.Forms.MessageBox]::Show("Profile assignment failed: $($_.Exception.Message)`r`n`r`nLine: $($_.InvocationInfo.ScriptLineNumber)`r`nCommand: $($_.InvocationInfo.Line)", 'Pick Gold Images', 'OK', 'Error') | Out-Null
                        }
                    }.GetNewClosure())
                }
            }
            $menu.Items.Add('-') | Out-Null
            $miClear = $menu.Items.Add('Clear (use global Deep-Scan creds)')
            $miClear.Add_Click({
                try {
                    if (-not $Script:ManualGoldImageCreds) { $Script:ManualGoldImageCreds = @{} }
                    $count = 0
                    foreach ($it in $checked) {
                        if (-not $it -or -not $it.Text) { continue }
                        $Script:ManualGoldImageCreds.Remove($it.Text) | Out-Null
                        if ($it.SubItems -and $it.SubItems.Count -gt 7) { $it.SubItems[7].Text = '' }
                        $count++
                    }
                    if ($lblStatusRef) { $lblStatusRef.Text = "Cleared per-VM cred for $count VM(s)." }
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("Clear failed: $($_.Exception.Message)`r`n`r`nLine: $($_.InvocationInfo.ScriptLineNumber)", 'Pick Gold Images', 'OK', 'Error') | Out-Null
                }
            }.GetNewClosure())
            $miMgr = $menu.Items.Add('Manage Credentials...')
            $miMgr.Add_Click({ Show-CredentialProfileDialog })
            $menu.Show($btnSetCred, 0, $btnSetCred.Height)
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Set Cred Profile failed: $($_.Exception.Message)`r`n`r`nLine: $($_.InvocationInfo.ScriptLineNumber)`r`nCommand: $($_.InvocationInfo.Line)", 'Pick Gold Images', 'OK', 'Error') | Out-Null
        }
    })

    $btnSave.Add_Click({
        # Use the session-wide checked set, not $lv.CheckedItems - the latter
        # only contains the rows currently passing the search filter.
        $picked = @($script:gpChecked)
        $Script:ManualGoldImages = $picked
        # Drop per-VM cred entries for VMs that are not in the saved list
        $stale = @($Script:ManualGoldImageCreds.Keys | Where-Object { $picked -notcontains $_ })
        foreach ($s in $stale) { $Script:ManualGoldImageCreds.Remove($s) | Out-Null }
        $dlgGold.DialogResult = 'OK'
        $dlgGold.Close()
    })

    [void]$dlgGold.ShowDialog($form)

    # Disconnect the picker's VC sessions so they do not leak into the main run
    foreach ($vcOne in $connected) {
        try { Disconnect-VIServer -Server $vcOne -Confirm:$false -Force | Out-Null } catch { }
    }
    if ($Script:ManualGoldImages.Count -gt 0) {
        $btnGold.Text = "Gold Images: $($Script:ManualGoldImages.Count) selected"
        $btnGold.BackColor = [System.Drawing.Color]::FromArgb(39, 174, 96); $btnGold.ForeColor = [System.Drawing.Color]::White
    }
}

# Log area: red-bordered panel containing the textbox.
# The panel's BackColor red shows as a 2px border around the textbox; when the
# user clicks Run, the disclaimer text is cleared and replaced by progress
# logs (the red border stays so the section keeps a visual identity).
$logFrame = New-Object System.Windows.Forms.Panel
# Sits below the help label (y=764, h=36 -> ends 800). 8 px gap.
$logFrame.Location = New-Object System.Drawing.Point(12, 808)
$logFrame.Size     = New-Object System.Drawing.Size(870, 100)
# Bottom|Left|Right (NOT Top) - the log frame stays a fixed height anchored
# to the bottom of the form. Vertical growth comes from the plugin tree
# group (anchored Top|Bottom), which absorbs the extra space.
$logFrame.Anchor   = [System.Windows.Forms.AnchorStyles]::Bottom -bor `
                     [System.Windows.Forms.AnchorStyles]::Left   -bor `
                     [System.Windows.Forms.AnchorStyles]::Right
$logFrame.BackColor = [System.Drawing.Color]::FromArgb(192, 57, 43)   # red border
$form.Controls.Add($logFrame)

# ---- Drag-resize splitter for the log frame ------------------------------
# Thin gray strip directly above the log frame (just under the help label
# at y=800). Click-and-drag UP grows the log, DOWN shrinks it. To keep
# the bottom-anchored controls (scope row, progress, button rows, help
# label) from being overlapped by an upward-growing log, every drag also
# shifts those controls up by the same delta. The plugin tree group
# shrinks/grows in lock-step. Cursor changes to HSplit (N/S arrows) on
# hover so the affordance is obvious.
$logSplit = New-Object System.Windows.Forms.Panel
$logSplit.Size     = New-Object System.Drawing.Size(870, 6)
$logSplit.Location = New-Object System.Drawing.Point(12, 802)
$logSplit.Anchor   = [System.Windows.Forms.AnchorStyles]::Bottom -bor `
                     [System.Windows.Forms.AnchorStyles]::Left   -bor `
                     [System.Windows.Forms.AnchorStyles]::Right
$logSplit.BackColor = [System.Drawing.Color]::FromArgb(170, 170, 170)
$logSplit.Cursor    = [System.Windows.Forms.Cursors]::HSplit
$form.Controls.Add($logSplit)

# The "followers" - bottom-anchored controls that sit between the plugin
# tree and the log frame. They get pushed up/down when the splitter is
# dragged so they are never overlapped by the resized log. Captured at
# MouseDown time (some of these references don't exist yet at the point
# this splitter is constructed - they're created later in the script).
$Script:logSplitDragging   = $false
$Script:logSplitStartY     = 0
$Script:logSplitStartTop   = 0
$Script:logSplitStartHt    = 0
$Script:logSplitStartGrpHt = 0
$Script:logSplitFollowers  = $null
$Script:logSplitStartFollowerTops = @()
$logSplit.Add_MouseDown({
    param($s, $e)
    $Script:logSplitDragging   = $true
    $Script:logSplitStartY     = [System.Windows.Forms.Cursor]::Position.Y
    $Script:logSplitStartTop   = $logFrame.Top
    $Script:logSplitStartHt    = $logFrame.Height
    $Script:logSplitStartGrpHt = $grpPlug.Height
    if ($null -eq $Script:logSplitFollowers) {
        # Build the follower list now - every bottom-band control that
        # exists. Variable-name lookup is dynamic so missing names are
        # silently skipped (avoids brittle ordering).
        $Script:logSplitFollowers = @()
        foreach ($n in @('scopeRow','progress','btnRun','btnOpen','btnImgCred','lblImgCred','btnClose','btnSpec','btnGold','btnCreds','btnAcctReq','lblRow2')) {
            $v = Get-Variable -Name $n -ValueOnly -Scope Script -ErrorAction SilentlyContinue
            if (-not $v) { $v = Get-Variable -Name $n -ValueOnly -Scope Global -ErrorAction SilentlyContinue }
            if (-not $v) { $v = Get-Variable -Name $n -ValueOnly -ErrorAction SilentlyContinue }
            if ($v) { $Script:logSplitFollowers += $v }
        }
    }
    $Script:logSplitStartFollowerTops = @()
    foreach ($c in $Script:logSplitFollowers) { $Script:logSplitStartFollowerTops += $c.Top }
})
$logSplit.Add_MouseMove({
    param($s, $e)
    if (-not $Script:logSplitDragging) { return }
    $delta = [System.Windows.Forms.Cursor]::Position.Y - $Script:logSplitStartY
    # Drag up = delta negative = log grows, tree shrinks. Clamp so neither
    # collapses below a usable minimum.
    $minLog = 60; $minGrp = 100
    $effectiveDelta = $delta
    if (($Script:logSplitStartHt - $effectiveDelta) -lt $minLog) {
        $effectiveDelta = $Script:logSplitStartHt - $minLog
    }
    if (($Script:logSplitStartGrpHt + $effectiveDelta) -lt $minGrp) {
        $effectiveDelta = $minGrp - $Script:logSplitStartGrpHt
    }
    $logFrame.Top    = $Script:logSplitStartTop + $effectiveDelta
    $logFrame.Height = $Script:logSplitStartHt - $effectiveDelta
    $grpPlug.Height  = $Script:logSplitStartGrpHt + $effectiveDelta
    $logSplit.Top    = $logFrame.Top - $logSplit.Height
    # Shift every bottom-band follower by the same delta so they don't
    # overlap with the resized log.
    for ($i = 0; $i -lt $Script:logSplitFollowers.Count; $i++) {
        $Script:logSplitFollowers[$i].Top = $Script:logSplitStartFollowerTops[$i] + $effectiveDelta
    }
})
$logSplit.Add_MouseUp({ $Script:logSplitDragging = $false })

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true; $logBox.ScrollBars = 'Vertical'; $logBox.ReadOnly = $true
$logBox.BorderStyle = 'None'
$logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$logBox.Location = New-Object System.Drawing.Point(2, 2)
$logBox.Size     = New-Object System.Drawing.Size(866, 96)
$logBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top    -bor `
                 [System.Windows.Forms.AnchorStyles]::Bottom -bor `
                 [System.Windows.Forms.AnchorStyles]::Left   -bor `
                 [System.Windows.Forms.AnchorStyles]::Right
$logBox.BackColor = [System.Drawing.Color]::White
$logFrame.Controls.Add($logBox)

# Pre-fill operator-instructions. Wiped on Run.
$logBox.Text = @"
Targets you selected on the welcome screen appear as ENABLED tabs above;
unselected targets are marked '(off)' and cannot be activated this session.

Fill in each enabled tab's Server FQDN, Username, Password (and Domain for
Horizon), then 'Test' the connection. When the Scope label below is GREEN
showing the targets you intend to run, click 'Run Health Check'.

Reports are written to the Output folder. Nothing is uploaded.
"@

$progress = New-Object System.Windows.Forms.ProgressBar
# Progress bar gets its own dedicated full-width row at y=664, between the
# scope row (y=620-650) and the top button row (y=692). Old layout placed
# the progress bar at (330, 696) with width 460 - it sat ON TOP of the
# 'Set Deep-Scan Creds...' button at (330, 692, 170, 32) and the optional
# help label at (508, 700), making one or the other unreachable depending
# on z-order. Putting the progress bar in its own row removes the overlap
# entirely so no BringToFront / Visible toggling is needed.
$progress.Location = New-Object System.Drawing.Point(12, 664)
$progress.Size     = New-Object System.Drawing.Size(870, 22)
$progress.Style    = 'Continuous'
$progress.Anchor   = [System.Windows.Forms.AnchorStyles]::Bottom -bor `
                     [System.Windows.Forms.AnchorStyles]::Left   -bor `
                     [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($progress)

$sync = [hashtable]::Synchronized(@{
    Log = New-Object System.Collections.ArrayList
    Done = $false; Error = $null; LastReport = $null
    PluginsTotal = 0; PluginsDone = 0
})

$logTimer = New-Object System.Windows.Forms.Timer
$logTimer.Interval = 200
# Wrap every tick body in try/catch. Ticks can fire after the form is
# closing or after one of the referenced controls / sync members has been
# disposed/null. Without this, a single null-ref throws a JIT pop-up at
# the user instead of being silently swallowed.
$logTimer.Add_Tick({
    try {
        if (-not $sync) { return }
        if ($sync.Log) {
            while ($sync.Log.Count -gt 0) {
                $line = $sync.Log[0]
                $sync.Log.RemoveAt(0)
                if ($logBox -and -not $logBox.IsDisposed) { $logBox.AppendText($line + "`r`n") }
            }
        }
        if ($sync.PluginsTotal -gt 0 -and $progress -and -not $progress.IsDisposed) {
            $progress.Maximum = $sync.PluginsTotal
            $progress.Value   = [Math]::Min($sync.PluginsDone, $progress.Maximum)
        }
        if ($sync.Done) {
            try { $logTimer.Stop() } catch { }
            if ($btnRun -and -not $btnRun.IsDisposed) {
                $btnRun.Enabled = $true; $btnRun.Text = 'Run Health Check'
            }
            if ($sync.Error) {
                [System.Windows.Forms.MessageBox]::Show("Run failed:`n`n$($sync.Error)", 'AuthorityGate HealthCheck', 'OK', 'Error') | Out-Null
            } elseif ($btnOpen -and -not $btnOpen.IsDisposed) {
                $btnOpen.Enabled = [bool]$sync.LastReport
            }
        }
    } catch {
        try { Write-Host "[!] logTimer tick swallowed: $($_.Exception.Message)" -ForegroundColor DarkYellow } catch { }
    }
})

# Generic Test-Connection handler factory.
# Horizon, vCenter, and Nutanix accept comma/semicolon-separated server
# lists (multi-pod / multi-vCenter / multi-target). The Test handler splits
# the same way the runspace does and reports per-server success / failure
# so a single bad FQDN does not mask a working second target.
function Register-TestHandler($ctrls, $kind, $rootPath) {
    $ctrls.Test.Add_Click({
        if (-not $ctrls.Server.Text -or -not $ctrls.User.Text -or -not $ctrls.Pass.Text) {
            [System.Windows.Forms.MessageBox]::Show("Enter $kind server, user, and password first.", 'Test', 'OK', 'Information') | Out-Null
            return
        }
        $sec = ConvertTo-SecureString $ctrls.Pass.Text -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential($ctrls.User.Text, $sec)

        # Backends that accept multi-target lists (per the GUI hint text).
        $multiKinds = @('Horizon','vCenter')
        $servers = if ($kind -in $multiKinds) {
            @($ctrls.Server.Text -split '[,;]\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        } else {
            @($ctrls.Server.Text.Trim())
        }
        if ($servers.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Server FQDN field is empty after splitting on , and ;.", 'Test', 'OK', 'Information') | Out-Null
            return
        }

        $results = New-Object System.Collections.Generic.List[string]
        $allOk = $true
        foreach ($srv in $servers) {
            try {
                switch ($kind) {
                    'Horizon' {
                        Import-Module (Join-Path $rootPath 'Modules\HorizonRest.psm1') -Force
                        Connect-HVRest -Server $srv -Credential $cred -Domain $ctrls.Domain.Text -SkipCertificateCheck:$ctrls.SkipCert.Checked | Out-Null
                        Disconnect-HVRest
                    }
                    'vCenter' {
                        if (-not (Get-Module -ListAvailable VMware.VimAutomation.Core)) { throw "PowerCLI not installed." }
                        Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
                        if ($ctrls.SkipCert.Checked) { Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null }
                        Connect-VIServer -Server $srv -Credential $cred -ErrorAction Stop | Out-Null
                        Disconnect-VIServer -Server $srv -Confirm:$false -Force | Out-Null
                    }
                    'AppVolumes' {
                        Import-Module (Join-Path $rootPath 'Modules\AppVolumesRest.psm1') -Force
                        Connect-AVRest -Server $srv -Credential $cred -SkipCertificateCheck:$ctrls.SkipCert.Checked | Out-Null
                        Disconnect-AVRest
                    }
                    'UAG' {
                        Import-Module (Join-Path $rootPath 'Modules\UAGRest.psm1') -Force
                        $port = [int]($ctrls.Port.Text)
                        Connect-UAGRest -Server $srv -Credential $cred -Port $port -SkipCertificateCheck:$ctrls.SkipCert.Checked | Out-Null
                        Disconnect-UAGRest
                    }
                    'NSX' {
                        Import-Module (Join-Path $rootPath 'Modules\NSXRest.psm1') -Force
                        Connect-NSXRest -Server $srv -Credential $cred -SkipCertificateCheck:$ctrls.SkipCert.Checked | Out-Null
                        Disconnect-NSXRest
                    }
                }
                $results.Add("[OK]   $srv") | Out-Null
            } catch {
                $allOk = $false
                $results.Add("[FAIL] $srv : $($_.Exception.Message)") | Out-Null
            }
        }
        $title = if ($allOk) { "$kind - all $($servers.Count) target(s) OK" } else { "$kind - some target(s) failed" }
        $icon  = if ($allOk) { 'Information' } else { 'Warning' }
        [System.Windows.Forms.MessageBox]::Show(($results -join "`r`n"), $title, 'OK', $icon) | Out-Null
    }.GetNewClosure())
}
Register-TestHandler $cHV  'Horizon'    $root
Register-TestHandler $cVC  'vCenter'    $root
Register-TestHandler $cAV  'AppVolumes' $root
Register-TestHandler $cUAG 'UAG'        $root
Register-TestHandler $cNSX 'NSX'        $root

# ---- Run handler ---------------------------------------------------------
$btnRun.Add_Click({
    # Pre-run license gate: block if no valid license token on file.
    # Surface the actual reason so the user knows whether to request a new
    # license, activate one they already received, or just refresh.
    try {
        $lic = Get-AGLicense
        if (-not $lic.Valid) {
            $msg = "Cannot run health check: $($lic.Reason)`r`n`r`nClick the License tab and either Request License (if you do not have one yet) or Activate License (if you have a token from email)."
            [System.Windows.Forms.MessageBox]::Show($msg, 'License required', 'OK', 'Warning') | Out-Null
            $tabs.SelectedTab = $tabLic
            & $Script:UpdateLicenseDisplay
            return
        }
        $Script:RunLicenseClaims = $lic.Claims
        $Script:RunStartedAt = Get-Date
        $Script:RunId = [guid]::NewGuid().ToString()
        # Best-effort flush of any queued telemetry from prior offline runs
        try { [void](Submit-AGUsageQueue) } catch { }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("License module error: $($_.Exception.Message)", 'License', 'OK', 'Error') | Out-Null
        return
    }

    $state.UseHorizon = $cHV.Use.Checked;  $state.HVServer = $cHV.Server.Text; $state.HVUser = $cHV.User.Text; $state.HVDomain = $cHV.Domain.Text; $state.HVSkipCert = $cHV.SkipCert.Checked
    $state.UseVCenter = $cVC.Use.Checked;  $state.VCServer = $cVC.Server.Text; $state.VCUser = $cVC.User.Text; $state.VCSkipCert = $cVC.SkipCert.Checked
    $state.UseAV      = $cAV.Use.Checked;  $state.AVServer = $cAV.Server.Text; $state.AVUser = $cAV.User.Text; $state.AVSkipCert = $cAV.SkipCert.Checked
    if ($cAV.PackagingVms) { $state.AVPackagingVms = $cAV.PackagingVms.Text }
    if ($cNTNX) {
        $state.UseNTNX     = [bool]$cNTNX.Use.Checked
        $state.NTNXServer  = $cNTNX.Server.Text
        $state.NTNXUser    = $cNTNX.User.Text
        $state.NTNXSkipCert = [bool]$cNTNX.SkipCert.Checked
        $state.NTNXPort    = [int]$cNTNX.Port.Text
    }
    if ($cVIDM) {
        $state.UseVIDM      = [bool]$cVIDM.Use.Checked
        $state.VIDMServer   = $cVIDM.Server.Text
        $state.VIDMClientId = $cVIDM.User.Text
        $state.VIDMSkipCert = [bool]$cVIDM.SkipCert.Checked
        $state.VIDMTenantPath = if ($cVIDM.TenantPath) { $cVIDM.TenantPath.Text } else { '/SAAS' }
    }
    if ($cUEM) {
        $state.UseUEM     = [bool]$cUEM.Use.Checked
        $state.UEMServer  = $cUEM.Server.Text
        $state.UEMUser    = $cUEM.User.Text
        $state.UEMSkipCert = [bool]$cUEM.SkipCert.Checked
    }
    $state.UseUAG     = $cUAG.Use.Checked; $state.UAGServer = $cUAG.Server.Text; $state.UAGUser = $cUAG.User.Text; $state.UAGSkipCert = $cUAG.SkipCert.Checked; $state.UAGPort = [int]$cUAG.Port.Text
    if ($cDEM) {
        $state.UseDEM = [bool]$cDEM.Use.Checked
        $state.DEMConfigShare  = $cDEM.ConfigShare.Text
        $state.DEMArchiveShare = $cDEM.ArchiveShare.Text
        $state.DEMAgentTarget  = $cDEM.AgentTarget.Text
    }
    $state.UseNSX     = $cNSX.Use.Checked; $state.NSXServer = $cNSX.Server.Text; $state.NSXUser = $cNSX.User.Text; $state.NSXSkipCert = $cNSX.SkipCert.Checked
    if ($cAD) {
        $state.UseAD = [bool]$cAD.Use.Checked
        # Read BOTH colDC (required) and colForest (optional). Earlier builds
        # only saved Forest, so $Global:ADServerFqdn never reached the
        # runspace and every AD plugin fell back to default-domain-discovery
        # ('Unable to find a default server with Active Directory Web
        # Services running'). Gate on DC, since the DC FQDN is what plugins
        # actually need for the -Server parameter.
        $rows = @()
        foreach ($r in $cAD.Grid.Rows) {
            $dc = [string]$r.Cells['colDC'].Value
            if (-not $dc -or -not $dc.Trim()) { continue }
            $f  = [string]$r.Cells['colForest'].Value
            $cp = [string]$r.Cells['colCred'].Value
            $rows += @{
                Server      = $dc.Trim()
                Forest      = if ($f) { $f.Trim() } else { '' }
                CredProfile = $cp
            }
        }
        $state.ADForests = $rows
    }
    $state.OutputPath = $tbOutPath.Text;   $state.GenerateHtml = $cbHtml.Checked
    $state.GenerateWord = $cbWord.Checked; $state.ShowWord = $cbShowWord.Checked; $state.DocAuthor = $tbAuthor.Text

    $disabled = New-Object System.Collections.ArrayList
    foreach ($cat in $tree.Nodes) { foreach ($p in $cat.Nodes) { if (-not $p.Checked) { [void]$disabled.Add($p.Tag) } } }
    $state.DisabledPlugins = $disabled.ToArray()
    Save-State

    # Defensive: trim whitespace from every Server FQDN so a stray space
    # doesn't pass the truthy check while still failing connect.
    $cHV.Server.Text  = $cHV.Server.Text.Trim()
    $cVC.Server.Text  = $cVC.Server.Text.Trim()
    $cAV.Server.Text  = $cAV.Server.Text.Trim()
    $cUAG.Server.Text = $cUAG.Server.Text.Trim()
    $cNSX.Server.Text = $cNSX.Server.Text.Trim()

    # Snapshot the FQDNs ONCE so every downstream read sees the same string.
    # This eliminates any race where the textbox might be modified between
    # the active-list calc and the SetVariable line.
    $hvFqdn   = $cHV.Server.Text
    $vcFqdn   = $cVC.Server.Text
    $avFqdn   = $cAV.Server.Text
    $ntnxFqdn = $cNTNX.Server.Text
    $vidmFqdn = $cVIDM.Server.Text
    $uemFqdn  = $cUEM.Server.Text
    $uagFqdn  = $cUAG.Server.Text
    $nsxFqdn  = $cNSX.Server.Text

    # STRICT: a tab is active ONLY if its 'Connect to this target' checkbox
    # is ticked AND its Server FQDN is filled in. Both required.
    $active = @()
    if ($cHV.Use.Checked   -and $hvFqdn)   { $active += 'Horizon' }
    if ($cVC.Use.Checked   -and $vcFqdn)   { $active += 'vCenter' }
    if ($cAV.Use.Checked   -and $avFqdn)   { $active += 'AppVolumes' }
    if ($cNTNX.Use.Checked -and $ntnxFqdn) { $active += 'Nutanix' }
    if ($cVIDM.Use.Checked -and $vidmFqdn) { $active += 'vIDM' }
    if ($cUEM.Use.Checked  -and $uemFqdn)  { $active += 'WS1UEM' }
    if ($cUAG.Use.Checked  -and $uagFqdn)  { $active += 'UAG' }
    if ($cNSX.Use.Checked  -and $nsxFqdn)  { $active += 'NSX' }
    # AD: shape is different (multi-row grid, no single Server textbox).
    # Active when the Use checkbox is ticked AND at least one row has a
    # populated DC FQDN. Lets AD run as the only target.
    $adRowCount = 0
    if ($cAD -and $cAD.Use.Checked -and $cAD.Grid) {
        foreach ($r in $cAD.Grid.Rows) {
            $dc = [string]$r.Cells['colDC'].Value
            if ($dc -and $dc.Trim()) { $adRowCount++ }
        }
    }
    if ($adRowCount -gt 0) { $active += 'AD' }

    # Also bail loudly if a Use checkbox is ticked but Server FQDN is empty
    # (clearer error than the generic "No active scope").
    $tickedButEmpty = @()
    if ($cVC.Use.Checked   -and -not $vcFqdn)   { $tickedButEmpty += 'vCenter' }
    if ($cHV.Use.Checked   -and -not $hvFqdn)   { $tickedButEmpty += 'Horizon' }
    if ($cAV.Use.Checked   -and -not $avFqdn)   { $tickedButEmpty += 'App Volumes' }
    if ($cNTNX.Use.Checked -and -not $ntnxFqdn) { $tickedButEmpty += 'Nutanix' }
    if ($cUAG.Use.Checked  -and -not $uagFqdn)  { $tickedButEmpty += 'UAG' }
    if ($cNSX.Use.Checked  -and -not $nsxFqdn)  { $tickedButEmpty += 'NSX' }
    if ($cAD -and $cAD.Use.Checked -and $adRowCount -eq 0) { $tickedButEmpty += 'AD (no forest rows added)' }
    if ($tickedButEmpty.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(
            ("Server FQDN is EMPTY for: " + ($tickedButEmpty -join ', ') + ".`r`n`r`nClick the tab(s) above and type the Server FQDN before clicking Run Health Check."),
            'AuthorityGate HealthCheck - Missing Server FQDN', 'OK', 'Warning') | Out-Null
        return
    }
    if ($active.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No active scope.`r`n`r`nTick the 'Connect to this target' checkbox AND fill in Server FQDN on at least one tab.`r`n`r`nQuick-select buttons (above the Run button) set the scope in one click - try 'vCenter Only' for a vSphere-only assessment.", 'AuthorityGate HealthCheck', 'OK', 'Warning') | Out-Null
        return
    }
    # Validate creds for each active tab
    $missing = @()
    if ('Horizon'    -in $active -and (-not $cHV.User.Text  -or -not $cHV.Pass.Text))  { $missing += 'Horizon' }
    if ('vCenter'    -in $active -and (-not $cVC.User.Text  -or -not $cVC.Pass.Text))  { $missing += 'vCenter' }
    if ('AppVolumes' -in $active -and (-not $cAV.User.Text  -or -not $cAV.Pass.Text))  { $missing += 'App Volumes' }
    if ('UAG'        -in $active -and (-not $cUAG.User.Text -or -not $cUAG.Pass.Text)) { $missing += 'UAG' }
    if ('NSX'        -in $active -and (-not $cNSX.User.Text -or -not $cNSX.Pass.Text)) { $missing += 'NSX' }
    if ($missing.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show("Missing username or password for: $($missing -join ', ').", 'AuthorityGate HealthCheck', 'OK', 'Warning') | Out-Null
        return
    }

    # ---- Pre-flight prerequisites -----------------------------------------
    # Block Run if a target is selected but its required PowerShell module
    # is not installed. Catching this here gives a clear actionable error
    # instead of a silent "vCenter Connect failed - 0 plugins ran" report.
    $missingModules = @()
    if ('vCenter' -in $active -and -not (Get-Module -ListAvailable -Name VMware.VimAutomation.Core)) {
        $missingModules += "vCenter selected but VMware PowerCLI is NOT installed.`r`n  Install with:  Install-Module -Name VMware.PowerCLI -Scope CurrentUser"
    }
    if ($missingModules.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(
            ("PREREQUISITE MISSING - Run aborted`r`n`r`n" + ($missingModules -join "`r`n`r`n")),
            'AuthorityGate HealthCheck', 'OK', 'Error') | Out-Null
        return
    }

    function MakeCred($u, $p) { if (-not $u -or -not $p) { return $null }; New-Object System.Management.Automation.PSCredential($u, (ConvertTo-SecureString $p -AsPlainText -Force)) }
    $hvCred  = if ('Horizon'    -in $active) { MakeCred $cHV.User.Text  $cHV.Pass.Text  } else { $null }
    # Decrypt the operator-selected ADAM credential profile NOW (UI thread)
    # so the runspace gets a ready-to-use PSCredential. Profile NAME selection
    # only happens via $Global:HVAdamProfileName (no real customer name is
    # baked into defaults). Decrypt failure is non-fatal - plugins fall back
    # to REST + SOAP.
    $adamCred = $null
    if ('Horizon' -in $active -and $Global:HVAdamProfileName) {
        try { $adamCred = Get-AGCredentialAsPSCredential -Name $Global:HVAdamProfileName } catch { $adamCred = $null }
    }
    $vcCred  = if ('vCenter'    -in $active) { MakeCred $cVC.User.Text  $cVC.Pass.Text  } else { $null }
    $avCred   = if ('AppVolumes' -in $active) { MakeCred $cAV.User.Text  $cAV.Pass.Text  } else { $null }
    $ntnxCred = if ('Nutanix'    -in $active) { MakeCred $cNTNX.User.Text $cNTNX.Pass.Text } else { $null }
    # vIDM uses ClientId/Secret rather than user/password - same MakeCred shape works.
    $vidmCred = if ('vIDM'       -in $active) { MakeCred $cVIDM.User.Text $cVIDM.Pass.Text } else { $null }
    $uemCred  = if ('WS1UEM'     -in $active) { MakeCred $cUEM.User.Text  $cUEM.Pass.Text  } else { $null }
    $uemApiKey = if ('WS1UEM'    -in $active) { [string]$cUEM.ApiKey.Text } else { '' }
    $uagCred  = if ('UAG'        -in $active) { MakeCred $cUAG.User.Text $cUAG.Pass.Text } else { $null }
    $nsxCred  = if ('NSX'        -in $active) { MakeCred $cNSX.User.Text $cNSX.Pass.Text } else { $null }

    foreach ($t in @($cHV.Pass, $cVC.Pass, $cAV.Pass, $cNTNX.Pass, $cVIDM.Pass, $cUEM.Pass, $cUEM.ApiKey, $cUAG.Pass, $cNSX.Pass)) { $t.Clear() }

    $sync.Log.Clear() | Out-Null
    $sync.Done = $false; $sync.Error = $null; $sync.LastReport = $null
    $sync.PluginsTotal = 0; $sync.PluginsDone = 0
    $logBox.Clear(); $progress.Value = 0
    $btnRun.Enabled = $false; $btnRun.Text = 'Running...'; $btnOpen.Enabled = $false
    $logTimer.Start()

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()

    # Capture every click-handler-side value in one struct so the runspace
    # can include it in the report and we can see if SetVariable lost anything.
    $clickSnapshot = @{
        ActiveList      = ($active -join ', ')
        HVFqdnSnapshot  = $hvFqdn
        VCFqdnSnapshot  = $vcFqdn
        AVFqdnSnapshot  = $avFqdn
        UAGFqdnSnapshot = $uagFqdn
        NSXFqdnSnapshot = $nsxFqdn
        VCFqdnLength    = $vcFqdn.Length
        VCFqdnHex       = if ($vcFqdn) { -join ([char[]]$vcFqdn | ForEach-Object { '{0:X2}' -f [int]$_ }) } else { '' }
    }

    # Compute the FQDN to pass per backend BEFORE any SetVariable. PS5.1 has
    # quirks with `$(...)` subexpressions inside method invocation arguments;
    # using plain pre-computed variables eliminates all of them.
    $hvServerToPass   = if ('Horizon'    -in $active) { [string]$hvFqdn }   else { '' }
    $vcServerToPass   = if ('vCenter'    -in $active) { [string]$vcFqdn }   else { '' }
    $avServerToPass   = if ('AppVolumes' -in $active) { [string]$avFqdn }   else { '' }
    $ntnxServerToPass = if ('Nutanix'    -in $active) { [string]$ntnxFqdn } else { '' }
    $vidmServerToPass = if ('vIDM'       -in $active) { [string]$vidmFqdn } else { '' }
    $uemServerToPass  = if ('WS1UEM'     -in $active) { [string]$uemFqdn }  else { '' }
    $uagServerToPass  = if ('UAG'        -in $active) { [string]$uagFqdn }  else { '' }
    $nsxServerToPass  = if ('NSX'        -in $active) { [string]$nsxFqdn }  else { '' }

    # Force [string] type so SetVariable doesn't receive a PSObject wrapper
    # whose deserialized form could come through as $null in the runspace.
    $hvServerToPass   = [string]$hvServerToPass
    $vcServerToPass   = [string]$vcServerToPass
    $avServerToPass   = [string]$avServerToPass
    $ntnxServerToPass = [string]$ntnxServerToPass
    $vidmServerToPass = [string]$vidmServerToPass
    $uemServerToPass  = [string]$uemServerToPass
    $uagServerToPass  = [string]$uagServerToPass
    $nsxServerToPass  = [string]$nsxServerToPass

    $proxy = $rs.SessionStateProxy
    $proxy.SetVariable('sync',          $sync)
    $proxy.SetVariable('rootPath',      $root)
    $proxy.SetVariable('runspaceVersion', $Script:HealthCheckVersion)
    $proxy.SetVariable('clickSnapshot', $clickSnapshot)
    $proxy.SetVariable('hvServer',      $hvServerToPass)
    $proxy.SetVariable('hvDomain',      [string]$cHV.Domain.Text)
    $proxy.SetVariable('hvSkip',        [bool]$cHV.SkipCert.Checked)
    $proxy.SetVariable('hvCredential',  $hvCred)
    $proxy.SetVariable('adamCredential', $adamCred)
    $proxy.SetVariable('adamProfileName', [string]$Global:HVAdamProfileName)
    $proxy.SetVariable('vcServer',      $vcServerToPass)
    $proxy.SetVariable('vcSkip',        [bool]$cVC.SkipCert.Checked)
    $proxy.SetVariable('vcCredential',  $vcCred)
    $proxy.SetVariable('avServer',      $avServerToPass)
    $proxy.SetVariable('avSkip',        [bool]$cAV.SkipCert.Checked)
    $proxy.SetVariable('avCredential',  $avCred)
    $proxy.SetVariable('ntnxServer',    $ntnxServerToPass)
    $proxy.SetVariable('ntnxPort',      [int]$cNTNX.Port.Text)
    $proxy.SetVariable('ntnxSkip',      [bool]$cNTNX.SkipCert.Checked)
    $proxy.SetVariable('ntnxCredential',$ntnxCred)
    $proxy.SetVariable('vidmServer',    $vidmServerToPass)
    $proxy.SetVariable('vidmTenantPath',[string]$cVIDM.TenantPath.Text)
    $proxy.SetVariable('vidmSkip',      [bool]$cVIDM.SkipCert.Checked)
    $proxy.SetVariable('vidmCredential',$vidmCred)
    $proxy.SetVariable('uemServer',     $uemServerToPass)
    $proxy.SetVariable('uemSkip',       [bool]$cUEM.SkipCert.Checked)
    $proxy.SetVariable('uemCredential', $uemCred)
    $proxy.SetVariable('uemApiKey',     $uemApiKey)
    $proxy.SetVariable('uagServer',     $uagServerToPass)
    $proxy.SetVariable('uagPort',       [int]$cUAG.Port.Text)
    $proxy.SetVariable('uagSkip',       [bool]$cUAG.SkipCert.Checked)
    $proxy.SetVariable('uagCredential', $uagCred)
    $proxy.SetVariable('nsxServer',     $nsxServerToPass)

    # IMMEDIATELY read back each Server variable from the runspace and add to
    # the snapshot. If GetVariable shows the value but the runspace's $vcServer
    # is empty later, the bug is in the runspace's variable lifecycle. If
    # GetVariable shows empty here, SetVariable itself dropped the value.
    $clickSnapshot.HVReadback  = [string]$proxy.GetVariable('hvServer')
    $clickSnapshot.VCReadback  = [string]$proxy.GetVariable('vcServer')
    $clickSnapshot.AVReadback  = [string]$proxy.GetVariable('avServer')
    $clickSnapshot.UAGReadback = [string]$proxy.GetVariable('uagServer')
    $clickSnapshot.NSXReadback = [string]$proxy.GetVariable('nsxServer')
    # Re-set clickSnapshot so the runspace sees the readback values too
    $proxy.SetVariable('clickSnapshot', $clickSnapshot)
    $proxy.SetVariable('nsxSkip',       [bool]$cNSX.SkipCert.Checked)
    $proxy.SetVariable('nsxCredential', $nsxCred)
    $proxy.SetVariable('outputPath',    $tbOutPath.Text)
    $proxy.SetVariable('imageScanCred', $Script:ImageScanCred)
    # CustomerName flows into the JSON sidecar so the AGI enricher can label
    # the engagement on its cover page. Defaults to empty if not set.
    $custName = if ($Script:CustomerName) { $Script:CustomerName } else { '' }
    $proxy.SetVariable('customerName',  $custName)
    # Licensing context for telemetry assembly inside the runspace.
    $proxy.SetVariable('runId',         $Script:RunId)
    $proxy.SetVariable('runStartedAt',  $Script:RunStartedAt)
    $proxy.SetVariable('machineFp',     (Get-AGMachineFingerprint))
    # Specialized scope hints. Each plugin checks for its $Global:* and
    # gracefully skips if not set. Empty values = scope not in use.
    $specImp = if ($Script:SpecImprivata) { @($Script:SpecImprivata -split "`r?`n" | Where-Object { $_.Trim() }) } else { @() }
    # Prefer the AppVolumes-tab value; fall back to the legacy Specialized
    # Scope value for state.json files written before the move.
    $tabAVP  = if ($cAV.PackagingVms -and $cAV.PackagingVms.Text) { $cAV.PackagingVms.Text } else { '' }
    $rawAVP  = if ($tabAVP) { $tabAVP } else { $Script:SpecAVPackagingVms }
    $specAVP = if ($rawAVP) { @($rawAVP -split "`r?`n" | Where-Object { $_.Trim() }) } else { @() }
    $proxy.SetVariable('specImprivataList',     $specImp)
    $proxy.SetVariable('specDEMShare',          $Script:SpecDEMShare)
    # DEM tab values flow through dedicated proxy variables so the runspace
    # can prefer them over the legacy specialized-scope single-share field.
    $proxy.SetVariable('demConfigShare',        ([string]$state.DEMConfigShare))
    $proxy.SetVariable('demArchiveShare',       ([string]$state.DEMArchiveShare))
    $proxy.SetVariable('demAgentTarget',        ([string]$state.DEMAgentTarget))
    $proxy.SetVariable('specADForest',          $Script:SpecADForest)
    $proxy.SetVariable('specADCredential',      $Script:SpecADCredential)
    # AD tab list. Each row is hashtable @{ Server; Forest; CredProfile }.
    # The runspace resolves CredProfile to a [pscredential] at run time.
    # NOTE on shape: $state.ADForests is hashtables when the row was just
    # saved by the GUI in-memory, OR PSCustomObjects when reloaded from
    # state.json (ConvertFrom-Json deserializes to PSCustomObject). Both
    # support direct dot-access ($r.Server / $r.Forest / $r.CredProfile),
    # so we use that uniformly. Empty/missing properties cast to ''.
    $adRows = @()
    if ($state.UseAD) {
        foreach ($r in @($state.ADForests)) {
            if (-not $r) { continue }
            $sv = ''; $fr = ''; $cp = ''
            try { $sv = [string]$r.Server      } catch { }
            try { $fr = [string]$r.Forest      } catch { }
            try { $cp = [string]$r.CredProfile } catch { }
            if ($sv) { $adRows += @{ Server = $sv; Forest = $fr; CredProfile = $cp } }
        }
    }
    $proxy.SetVariable('adForests', $adRows)
    $proxy.SetVariable('specAVPackagingVms',    $specAVP)
    $proxy.SetVariable('specMFAExternalCheck',  [bool]$Script:SpecMFAExternalCheck)
    $proxy.SetVariable('manualGoldImages',      @($Script:ManualGoldImages))
    # Per-VM credential override map. Plugin layer resolves the profile name
    # to a [pscredential] via Get-AGCredentialAsPSCredential at scan time.
    $proxy.SetVariable('manualGoldImageCreds',  $Script:ManualGoldImageCreds)
    $proxy.SetVariable('genHtml',       [bool]$cbHtml.Checked)
    $proxy.SetVariable('genWord',       [bool]$cbWord.Checked)
    $proxy.SetVariable('showWord',      [bool]$cbShowWord.Checked)
    $proxy.SetVariable('docAuthor',     $tbAuthor.Text)
    $proxy.SetVariable('disabledPlugins', $disabled.ToArray())

    $ps = [powershell]::Create(); $ps.Runspace = $rs
    $null = $ps.AddScript({
        function Log($msg) { [void]$sync.Log.Add($msg) }
        try {
            Set-Location $rootPath
            . (Join-Path $rootPath 'GlobalVariables.ps1')

            Add-Type -AssemblyName System.Web | Out-Null
            Import-Module (Join-Path $rootPath 'Modules\HorizonRest.psm1')    -Force
            Import-Module (Join-Path $rootPath 'Modules\HorizonSoap.psm1')    -Force -ErrorAction SilentlyContinue
            Import-Module (Join-Path $rootPath 'Modules\HorizonADAM.psm1')    -Force -ErrorAction SilentlyContinue
            Import-Module (Join-Path $rootPath 'Modules\HtmlReport.psm1')     -Force
            Import-Module (Join-Path $rootPath 'Modules\AppVolumesRest.psm1') -Force
            Import-Module (Join-Path $rootPath 'Modules\NutanixRest.psm1')    -Force
            Import-Module (Join-Path $rootPath 'Modules\VIDMRest.psm1')       -Force -ErrorAction SilentlyContinue
            Import-Module (Join-Path $rootPath 'Modules\UEMRest.psm1')        -Force -ErrorAction SilentlyContinue
            Import-Module (Join-Path $rootPath 'Modules\UAGRest.psm1')        -Force
            Import-Module (Join-Path $rootPath 'Modules\NSXRest.psm1')        -Force
            Import-Module (Join-Path $rootPath 'Modules\VeeamRest.psm1')      -Force -ErrorAction SilentlyContinue
            Import-Module (Join-Path $rootPath 'Modules\InfraServerScan.psm1') -Force -ErrorAction SilentlyContinue
            Import-Module (Join-Path $rootPath 'Modules\GuestImageScan.psm1')  -Force -ErrorAction SilentlyContinue
            # Expose the resolved root to plugins as $Global:HVRoot so they
            # can locate sibling modules without their own path arithmetic
            # (which has bitten us when ZIP extractions create nested folders).
            $Global:HVRoot = $rootPath

            $hvSession = $null; $vcConnected = $false; $avSession = $null; $uagSession = $null; $nsxSession = $null
            $ntnxSessions = @{}; $ntnxSession = $null
            $vidmSession = $null; $uemSession = $null

            # Echo what the runspace actually received - if the GUI thinks
            # vCenter is active but vcServer arrived empty, this surfaces it
            # immediately rather than 246 plugins later.
            Log "[i] HealthCheck v${runspaceVersion} starting"
            Log "[i] Runspace received: hvServer='$hvServer' vcServer='$vcServer' avServer='$avServer' ntnxServer='$ntnxServer' uagServer='$uagServer' nsxServer='$nsxServer'"

            # Track every connection attempt so the report shows what worked + what failed.
            $connAttempts = New-Object System.Collections.ArrayList

            # --- Per-step diagnosis: DNS -> ICMP -> TCP -> TLS -> Auth -------
            # Distinguishes timeout / refused / unreachable. Probes alt
            # vCenter ports (5480 VAMI, 8443 host UI) when the primary port
            # is closed so the report can suggest "try a different port".
            function Test-Tcp {
                param([string]$Server, [int]$Port, [int]$TimeoutMs = 10000)
                $r = [pscustomobject]@{ Ok=$false; Error=''; SocketError='' }
                $tcp = $null
                try {
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    $iar = $tcp.BeginConnect($Server, $Port, $null, $null)
                    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) {
                        $r.Error = "TIMEOUT after $($TimeoutMs/1000)s (no SYN-ACK received)"
                        $r.SocketError = 'TimedOut'
                    } else {
                        $tcp.EndConnect($iar)
                        $r.Ok = $true
                    }
                } catch [System.Net.Sockets.SocketException] {
                    $r.SocketError = $_.Exception.SocketErrorCode.ToString()
                    $r.Error = "$($r.SocketError) - $($_.Exception.Message)"
                } catch {
                    $r.Error = $_.Exception.Message
                } finally {
                    if ($tcp) { try { $tcp.Close() } catch { } }
                }
                $r
            }

            function Test-BackendReachability {
                param([string]$ServerHost, [int]$Port = 443, [int[]]$AltPorts = @())
                $r = [pscustomobject]@{
                    DNSResolved   = $false
                    DNSDetails    = ''
                    PingMs        = -1
                    TCPReachable  = $false
                    TCPError      = ''
                    AltPortsOpen  = ''
                    TLSHandshake  = $false
                    Diagnosis     = ''
                    DiagCommands  = ''
                }
                $r.DiagCommands = "nslookup $ServerHost ; Test-NetConnection $ServerHost -Port $Port ; ping $ServerHost ; tracert $ServerHost"

                # ---- DNS
                try {
                    $ips = [System.Net.Dns]::GetHostAddresses($ServerHost) | ForEach-Object { $_.IPAddressToString }
                    $r.DNSResolved = $true
                    $r.DNSDetails  = ($ips -join ', ')
                } catch {
                    $r.Diagnosis = "DNS resolution FAILED for '$ServerHost'. The FQDN is wrong, OR your machine's DNS server can't resolve internal names (VPN not connected? Wrong DNS suffix?). Run nslookup $ServerHost to confirm."
                    return $r
                }

                # ---- ICMP ping (separate signal: is the host alive?)
                try {
                    $p = New-Object System.Net.NetworkInformation.Ping
                    $reply = $p.Send($ServerHost, 2000)
                    if ($reply.Status -eq 'Success') { $r.PingMs = $reply.RoundtripTime }
                } catch { }

                # ---- TCP on the requested port
                $tcp = Test-Tcp -Server $ServerHost -Port $Port -TimeoutMs 10000
                if ($tcp.Ok) {
                    $r.TCPReachable = $true
                } else {
                    $r.TCPError = $tcp.Error
                    # Try alternate ports the operator may have meant
                    $openAlts = @()
                    foreach ($ap in $AltPorts) {
                        $t = Test-Tcp -Server $ServerHost -Port $ap -TimeoutMs 5000
                        if ($t.Ok) { $openAlts += "$ap (open)" }
                    }
                    $r.AltPortsOpen = ($openAlts -join ', ')

                    # Build a specific diagnosis from the error fingerprint
                    $hint = switch -Wildcard ($tcp.SocketError) {
                        'ConnectionRefused' { "host is up but NOTHING is listening on TCP/$Port (the service is stopped, or vCenter is on a different port - check VAMI 5480 or alt-HTTPS 8443)." }
                        'TimedOut'          {
                            if ($r.PingMs -ge 0) { "host responds to ICMP ($($r.PingMs)ms) but TCP/$Port silently dropped. Causes: vCenter service down (vmware-vpxd), inbound ACL on the vCenter VM (host-based firewall), upstream stateful firewall dropping new flows, OR your source IP is not allowed by vCenter's source-IP allow-list." }
                            else                 { "host did NOT respond to ICMP and TCP/$Port timed out. Causes: VPN not connected, host powered off, routing missing, or all traffic blocked upstream." }
                        }
                        'NetworkUnreachable' { "no route to the host's network. Check VPN / routing table." }
                        'HostUnreachable'    { "router responded 'Destination Host Unreachable' (host is down or out of subnet)." }
                        default              { "TCP error '$($tcp.SocketError)': $($tcp.Error)" }
                    }
                    $altHint = if ($openAlts.Count -gt 0) { " Alternate ports OPEN on this host: $($openAlts -join ', '). Did you mean one of those?" } else { '' }
                    $r.Diagnosis = "TCP/$Port to $ServerHost ($($r.DNSDetails)) FAILED: $hint$altHint"
                    return $r
                }

                # ---- TLS handshake
                try {
                    $tcp2 = New-Object System.Net.Sockets.TcpClient
                    $tcp2.Connect($ServerHost, $Port)
                    $stream = $tcp2.GetStream()
                    $ssl = New-Object System.Net.Security.SslStream($stream, $false, ({$true} -as [System.Net.Security.RemoteCertificateValidationCallback]))
                    $ssl.AuthenticateAsClient($ServerHost)
                    $r.TLSHandshake = $true
                    $ssl.Close(); $tcp2.Close()
                } catch {
                    $r.Diagnosis = "TLS handshake to $ServerHost`:$Port FAILED. Network is reachable but TLS rejected: $($_.Exception.Message). Common causes: server cert expired/invalid, server only allows TLS 1.0 (PowerShell 5.1 needs Tls12 enabled), or man-in-the-middle proxy."
                    return $r
                }

                $r.Diagnosis = "Network OK. DNS=$($r.DNSDetails). Ping=$(if ($r.PingMs -ge 0) { "$($r.PingMs)ms" } else { 'no ICMP reply' }). TCP/$Port + TLS handshake successful."
                $r
            }

            function Build-ConnRow {
                param([string]$Target, [string]$Server, [int]$Port = 443)
                $alt = switch ($Target) {
                    'vCenter' { @(5480, 8443) }    # VAMI, alt-HTTPS console
                    'UAG'     { @(443, 9443) }     # both UAG ports
                    default   { @() }
                }
                $reach = Test-BackendReachability -ServerHost $Server -Port $Port -AltPorts $alt
                [pscustomobject]@{
                    Target       = $Target
                    Server       = $Server
                    DNSResolved  = $reach.DNSResolved
                    DNSIp        = $reach.DNSDetails
                    PingMs       = $reach.PingMs
                    TCPReachable = $reach.TCPReachable
                    AltPorts     = $reach.AltPortsOpen
                    TLSHandshake = $reach.TLSHandshake
                    Result       = 'Failed'
                    Diagnosis    = $reach.Diagnosis
                    DiagCommands = $reach.DiagCommands
                    ErrorMessage = ''
                }
            }

            # Horizon multi-pod: hvServer may be a comma/semicolon-separated
            # list of Connection Server FQDNs. Connect to each, store every
            # session in $hvSessions{fqdn}. The Horizon plugin loop below
            # iterates this map, pointing $Script:HVSession at one pod at a
            # time and tagging every emitted row with Pod=<fqdn>.
            $hvSessions = @{}
            if ($hvServer) {
                $hvList = @($hvServer -split '[,;]\s*' | Where-Object { $_.Trim() })
                # Expose the operator-typed CS FQDN list to plugins so the
                # WinRM-fallback CS Inventory plugin (10/06) can probe each
                # CS directly when REST returns stub-only data on Horizon 8.6.
                $Global:HVServer = $hvServer
                $Global:HVConnectedFqdnList = $hvList
                # ADAM (AD-LDS) credential plumbing - operator-configurable,
                # never defaulted to a real account. Plugins read the cred
                # from $Global:HVAdamCredential. Profile name is exposed
                # for the diagnostic row that reports which profile was used.
                $Global:HVAdamCredential = $adamCredential
                $Global:HVAdamProfileName = $adamProfileName
                Log "[+] Horizon pod list: $($hvList -join ', ')"
                foreach ($hvOne in $hvList) {
                    Log "[+] Probing Horizon $hvOne ..."
                    $row = Build-ConnRow -Target 'Horizon' -Server $hvOne -Port 443
                    if (-not $row.TLSHandshake -and -not $hvSkip) {
                        Log "[!] Horizon $($hvOne): $($row.Diagnosis)"
                    } else {
                        Log "[+] Horizon $hvOne network OK; logging in ..."
                        try {
                            $sess = Add-HVRestSession -Server $hvOne -Credential $hvCredential -Domain $hvDomain -SkipCertificateCheck:$hvSkip
                            if ($sess) {
                                $hvSessions[$hvOne] = $sess
                                # First successful connection becomes the
                                # legacy "active" session for any plugin not
                                # wrapped by the multi-pod loop.
                                if (-not $hvSession) { $hvSession = $sess }
                                $row.Result = 'Connected'
                                $row.Diagnosis = 'Authenticated successfully.'
                                Log "[+] Horizon $hvOne connected."

                                # SOAP fallback connect: when VMware.Hv.Helper
                                # is installed, also open a SOAP session against
                                # the same CS so plugins can pull full pod
                                # inventory + per-pool entitlements via the
                                # snap-in when REST returns stub data on
                                # Horizon 8.6. SOAP connect is best-effort -
                                # if it fails we keep going with REST only.
                                if (Get-Command Test-HVSoapAvailable -ErrorAction SilentlyContinue) {
                                    if (Test-HVSoapAvailable) {
                                        try {
                                            Connect-HVSoap -Server $hvOne -Credential $hvCredential -Domain $hvDomain -SkipCertificateCheck:$hvSkip | Out-Null
                                            Log "[+] Horizon $hvOne SOAP fallback connected."
                                        } catch {
                                            Log "[i] Horizon $hvOne SOAP fallback unavailable: $($_.Exception.Message)"
                                        }
                                    }
                                }
                            }
                        } catch {
                            $row.ErrorMessage = $_.Exception.Message
                            $row.Diagnosis = "Auth failed: $($_.Exception.Message)"
                            Log "[!] Horizon $hvOne auth failed: $($_.Exception.Message)"
                        }
                    }
                    $null = $connAttempts.Add($row)
                }
            }
            if ($vcServer) {
                # Multi-vCenter: vcServer may be a comma-/semicolon-separated
                # list of FQDNs. Build a connection-row per server, probe each,
                # connect to each. PowerCLI multi-server mode aggregates output.
                $vcList = @($vcServer -split '[,;]\s*' | Where-Object { $_.Trim() })
                Log "[+] vCenter list: $($vcList -join ', ')"
                $hasPowerCLI = [bool](Get-Module -ListAvailable VMware.VimAutomation.Core)
                if ($hasPowerCLI) {
                    Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
                    if ($vcSkip) { Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null }
                    Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Confirm:$false -Scope Session | Out-Null
                }
                foreach ($vcOne in $vcList) {
                    Log "[+] Probing vCenter $vcOne ..."
                    $row = Build-ConnRow -Target 'vCenter' -Server $vcOne -Port 443
                    if (-not $hasPowerCLI) {
                        $row.Diagnosis = "VMware PowerCLI is NOT installed. Run Install-Prerequisites.cmd, or: Install-Module -Name VMware.PowerCLI -Scope CurrentUser"
                        $row.ErrorMessage = $row.Diagnosis
                        Log "[!] PowerCLI not installed - vSphere plugins will skip."
                    } elseif (-not $row.TLSHandshake -and -not $vcSkip) {
                        Log "[!] vCenter $($vcOne): $($row.Diagnosis)"
                    } else {
                        try {
                            Connect-VIServer -Server $vcOne -Credential $vcCredential -ErrorAction Stop | Out-Null
                            $vcConnected = $true
                            $row.Result = 'Connected'
                            $row.Diagnosis = 'Authenticated successfully.'
                            Log "[+] vCenter connected: $vcOne"
                        } catch {
                            $row.ErrorMessage = $_.Exception.Message
                            $row.Diagnosis = "Auth failed: $($_.Exception.Message)"
                            Log "[!] vCenter auth failed for $($vcOne): $($_.Exception.Message)"
                        }
                    }
                    $null = $connAttempts.Add($row)
                }
            }
            if ($avServer) {
                Log "[+] Probing App Volumes $avServer ..."
                $row = Build-ConnRow -Target 'AppVolumes' -Server $avServer -Port 443
                if (-not $row.TLSHandshake -and -not $avSkip) {
                    Log "[!] App Volumes: $($row.Diagnosis)"
                } else {
                    Log "[+] App Volumes network OK; logging in ..."
                    try {
                        $avSession = Connect-AVRest -Server $avServer -Credential $avCredential -SkipCertificateCheck:$avSkip
                        $row.Result = 'Connected'
                        $row.Diagnosis = 'Authenticated successfully.'
                        Log "[+] App Volumes connected."
                    } catch {
                        $row.ErrorMessage = $_.Exception.Message
                        $row.Diagnosis = "Auth failed: $($_.Exception.Message)"
                        Log "[!] App Volumes auth failed: $($_.Exception.Message)"
                    }
                }
                $null = $connAttempts.Add($row)
            }
            if ($ntnxServer) {
                # Multi-target Nutanix: same comma/semicolon split as Horizon.
                $ntnxList = @($ntnxServer -split '[,;]\s*' | Where-Object { $_.Trim() })
                Log "[+] Nutanix target list: $($ntnxList -join ', ')"
                foreach ($ntnxOne in $ntnxList) {
                    Log "[+] Probing Nutanix Prism $($ntnxOne):$($ntnxPort) ..."
                    $row = Build-ConnRow -Target 'Nutanix' -Server $ntnxOne -Port $ntnxPort
                    $row.Server = "$($ntnxOne):$($ntnxPort)"
                    if (-not $row.TLSHandshake -and -not $ntnxSkip) {
                        Log "[!] Nutanix $($ntnxOne): $($row.Diagnosis)"
                    } else {
                        Log "[+] Nutanix $ntnxOne network OK; logging in ..."
                        try {
                            $sess = Add-NTNXRestSession -Server $ntnxOne -Credential $ntnxCredential -Port $ntnxPort -SkipCertificateCheck:$ntnxSkip
                            if ($sess) {
                                $ntnxSessions["${ntnxOne}:${ntnxPort}"] = $sess
                                if (-not $ntnxSession) { $ntnxSession = $sess }
                                $row.Result = 'Connected'
                                $row.Diagnosis = "Authenticated as $($ntnxCredential.UserName)."
                                Log "[+] Nutanix $ntnxOne connected."
                            }
                        } catch {
                            $row.ErrorMessage = $_.Exception.Message
                            $row.Diagnosis = "Auth failed: $($_.Exception.Message)"
                            Log "[!] Nutanix $ntnxOne auth failed: $($_.Exception.Message)"
                        }
                    }
                    $null = $connAttempts.Add($row)
                }
            }
            if ($vidmServer) {
                Log "[+] Probing Workspace ONE Access (vIDM) $vidmServer ..."
                $row = Build-ConnRow -Target 'vIDM' -Server $vidmServer -Port 443
                if (-not $row.TLSHandshake -and -not $vidmSkip) {
                    Log "[!] vIDM: $($row.Diagnosis)"
                } else {
                    try {
                        $clientId = if ($vidmCredential) { $vidmCredential.UserName } else { $null }
                        $clientSec = if ($vidmCredential) { $vidmCredential.GetNetworkCredential().Password } else { $null }
                        if (-not $clientId -or -not $clientSec) { throw 'OAuth Client ID / Shared Secret are both required.' }
                        $vidmSession = Connect-VIDMRest -Server $vidmServer -ClientId $clientId -ClientSecret $clientSec -TenantPath $vidmTenantPath -SkipCertificateCheck:$vidmSkip
                        $row.Result = 'Connected'
                        $row.Diagnosis = 'OAuth client_credentials grant succeeded.'
                        Log "[+] vIDM connected."
                    } catch {
                        $row.ErrorMessage = $_.Exception.Message
                        $row.Diagnosis = "Auth failed: $($_.Exception.Message)"
                        Log "[!] vIDM auth failed: $($_.Exception.Message)"
                    }
                }
                $null = $connAttempts.Add($row)
            }
            if ($uemServer) {
                Log "[+] Probing Workspace ONE UEM $uemServer ..."
                $row = Build-ConnRow -Target 'WS1UEM' -Server $uemServer -Port 443
                if (-not $row.TLSHandshake -and -not $uemSkip) {
                    Log "[!] WS1 UEM: $($row.Diagnosis)"
                } else {
                    try {
                        if (-not $uemApiKey) { throw 'aw-tenant-code (API key) is required - paste it in the WS1 UEM tab.' }
                        $uemSession = Connect-UEMRest -Server $uemServer -Credential $uemCredential -ApiKey $uemApiKey -SkipCertificateCheck:$uemSkip
                        $row.Result = 'Connected'
                        $row.Diagnosis = "Authenticated as $($uemCredential.UserName)."
                        Log "[+] WS1 UEM connected."
                    } catch {
                        $row.ErrorMessage = $_.Exception.Message
                        $row.Diagnosis = "Auth failed: $($_.Exception.Message)"
                        Log "[!] WS1 UEM auth failed: $($_.Exception.Message)"
                    }
                }
                $null = $connAttempts.Add($row)
            }
            if ($uagServer) {
                Log "[+] Probing UAG $($uagServer):$($uagPort) ..."
                $row = Build-ConnRow -Target 'UAG' -Server $uagServer -Port $uagPort
                $row.Server = "$($uagServer):$($uagPort)"
                if (-not $row.TLSHandshake -and -not $uagSkip) {
                    Log "[!] UAG: $($row.Diagnosis)"
                } else {
                    Log "[+] UAG network OK; logging in ..."
                    try {
                        $uagSession = Connect-UAGRest -Server $uagServer -Credential $uagCredential -Port $uagPort -SkipCertificateCheck:$uagSkip
                        $row.Result = 'Connected'
                        $row.Diagnosis = 'Authenticated successfully.'
                        Log "[+] UAG connected."
                    } catch {
                        $row.ErrorMessage = $_.Exception.Message
                        $row.Diagnosis = "Auth failed: $($_.Exception.Message)"
                        Log "[!] UAG auth failed: $($_.Exception.Message)"
                    }
                }
                $null = $connAttempts.Add($row)
            }
            if ($nsxServer) {
                Log "[+] Probing NSX $nsxServer ..."
                $row = Build-ConnRow -Target 'NSX' -Server $nsxServer -Port 443
                if (-not $row.TLSHandshake -and -not $nsxSkip) {
                    Log "[!] NSX: $($row.Diagnosis)"
                } else {
                    Log "[+] NSX network OK; logging in ..."
                    try {
                        $nsxSession = Connect-NSXRest -Server $nsxServer -Credential $nsxCredential -SkipCertificateCheck:$nsxSkip
                        $row.Result = 'Connected'
                        $row.Diagnosis = 'Authenticated successfully.'
                        Log "[+] NSX connected."
                    } catch {
                        $row.ErrorMessage = $_.Exception.Message
                        $row.Diagnosis = "Auth failed: $($_.Exception.Message)"
                        Log "[!] NSX auth failed: $($_.Exception.Message)"
                    }
                }
                $null = $connAttempts.Add($row)
            }

            $Global:HVSession   = $hvSession
            $Global:NTNXSession = $ntnxSession
            $Global:VIDMSession = $vidmSession
            $Global:UEMSession  = $uemSession
            $Global:VCConnected = $vcConnected
            # Surface the connected vCenter FQDN so plugins can call
            # `Get-View -Server $Global:VCServer` directly. PowerCLI's
            # `Get-VIServer -ErrorAction SilentlyContinue` historically failed
            # with "missing mandatory parameter: Server" on certain builds,
            # so plugins should prefer `$Global:VCServer` or `$global:DefaultVIServers`.
            if ($vcConnected -and $vcServer) { $Global:VCServer = $vcServer }
            $Global:AVSession   = $avSession
            $Global:UAGSession  = $uagSession
            $Global:NSXSession  = $nsxSession
            # Make the report output folder visible to plugins so the
            # gold-image deep-scan can write per-VM JSON dumps
            # alongside the main HTML/JSON reports.
            if (-not (Test-Path $outputPath)) { New-Item $outputPath -ItemType Directory -Force | Out-Null }
            $Global:HVOutputPath = $outputPath
            # Surface the optional image-scan credential to the plugin layer.
            # When set, the gold-image / RDSH-master / AppVolumes-packaging
            # deep-scan plugins probe the guest via WinRM (Tier 2). Without it
            # they emit Tier 1 (vCenter-side) findings only.
            if ($imageScanCred) { $Global:HVImageScanCredential = $imageScanCred }
            # Specialized-scope hints. Each plugin reads $Global:* and skips
            # gracefully when its hint is not set.
            if ($specImprivataList    -and @($specImprivataList).Count -gt 0)   { $Global:ImprivataApplianceList = @($specImprivataList) }
            # DEM scope: prefer dedicated tab values when supplied; fall back
            # to the legacy specialized-scope single-share field for compat.
            if ($demConfigShare)  { $Global:DEMConfigShare  = $demConfigShare }
            elseif ($specDEMShare) { $Global:DEMConfigShare = $specDEMShare }
            if ($demArchiveShare) { $Global:DEMArchiveShare = $demArchiveShare }
            if ($demAgentTarget)  { $Global:DEMAgentTarget  = $demAgentTarget }
            # AD scope: prefer the dedicated AD tab list (per-row Server/Forest/CredProfile).
            # Falls back to the legacy specialized-scope single-forest field for backwards
            # compatibility when the AD tab is empty.
            # CredentialProfiles MUST be imported before the AD-scope block since
            # we call Get-AGCredentialAsPSCredential to decrypt the saved profile
            # for the AD cmdlet -Credential parameter. Previously this import
            # was below the block, so the call silently failed (catch swallowed
            # 'command not recognized'), $cred stayed $null, AD plugins
            # auth-failed with SSPI on non-domain-joined runners.
            Import-Module (Join-Path $rootPath 'Modules\CredentialProfiles.psm1') -Force -Global -ErrorAction SilentlyContinue
            if ($adForests -and @($adForests).Count -gt 0) {
                # Try to load the AD module up front so we can auto-discover
                # forest FQDN from server when the operator left Forest blank.
                $adModuleAvailable = $false
                try { Import-Module ActiveDirectory -ErrorAction Stop -Global; $adModuleAvailable = $true } catch { }

                $resolvedAD = New-Object System.Collections.ArrayList
                foreach ($adr in @($adForests)) {
                    $cred = $null
                    if ($adr.CredProfile) {
                        try { $cred = Get-AGCredentialAsPSCredential -Name $adr.CredProfile } catch { }
                    }
                    $serverIn = [string]$adr.Server
                    $forestIn = [string]$adr.Forest
                    # Auto-discover forest from the DC if the operator left it blank.
                    if (-not $forestIn -and $adModuleAvailable -and $serverIn) {
                        try {
                            $domArgs = @{ Server = $serverIn; ErrorAction = 'Stop' }
                            if ($cred) { $domArgs.Credential = $cred }
                            $disc = Get-ADDomain @domArgs
                            if ($disc -and $disc.Forest) { $forestIn = [string]$disc.Forest }
                        } catch { }
                    }
                    [void]$resolvedAD.Add(@{ Server = $serverIn; Forest = $forestIn; Credential = $cred })
                }
                $Global:ADForests = $resolvedAD.ToArray()
                # Legacy single-forest globals = first row's discovered values, so unmodified
                # plugins keep working. ADServerFqdn = the DC (used for -Server). ADForestFqdn
                # = the forest identity (used for Get-ADForest -Identity AND legacy plugins
                # that still pass it as -Server). When forest is unknown after auto-discovery,
                # fall back to the server FQDN; that works if the user typed the FQDN form
                # (DC FQDN like dc01.example.local) but fails for short hostnames.
                $first = $resolvedAD[0]
                $Global:ADServerFqdn = $first.Server
                $Global:ADForestFqdn = if ($first.Forest) { $first.Forest } else { $first.Server }
                if ($first.Credential) { $Global:ADCredential = $first.Credential }
            } elseif ($specADForest) {
                $Global:ADForestFqdn = $specADForest
                $Global:ADServerFqdn = $specADForest
                if ($specADCredential) { $Global:ADCredential = $specADCredential }
                $Global:ADForests = @(@{ Server = $specADForest; Forest = $specADForest; Credential = $specADCredential })
            }
            if ($specAVPackagingVms   -and @($specAVPackagingVms).Count -gt 0)  { $Global:AVPackagingVmHints     = @($specAVPackagingVms) }
            if ($specMFAExternalCheck) { $Global:MFAExternalProbe = $true }
            # Manually-picked gold image VM names (operator-supplied via the
            # "Pick Gold Images..." dialog). The deep-scan plugin merges this
            # with the Horizon-discovered set.
            if ($manualGoldImages    -and @($manualGoldImages).Count -gt 0)    { $Global:HVManualGoldImageList = @($manualGoldImages) }
            # Per-VM credential override map flows in raw; plugin layer
            # resolves profile names to [pscredential]s on demand.
            if ($manualGoldImageCreds -and $manualGoldImageCreds.Count -gt 0)  { $Global:HVManualGoldImageCreds = $manualGoldImageCreds }
            # CredentialProfiles already imported above for the AD-scope block.

            # ---- Build the list of *connected* backends. A category whose
            # required backend isn't connected is skipped wholesale (its
            # plugins don't run, don't appear in the report).
            $connectedBackends = @()
            if ($hvSession)   { $connectedBackends += 'Horizon' }
            if ($vcConnected) { $connectedBackends += 'vCenter' }
            if ($avSession)   { $connectedBackends += 'AppVolumes' }
            if ($uagSession)  { $connectedBackends += 'UAG' }
            if ($nsxSession)  { $connectedBackends += 'NSX' }
            if ($vidmSession) { $connectedBackends += 'vIDM' }
            if ($uemSession)  { $connectedBackends += 'WS1UEM' }
            if ($Global:ADServerFqdn) { $connectedBackends += 'AD' }
            # Plugins read the connected-backend list via $Global:HVConnectedBackends
            # to drive their per-category Probe Diagnosis row + RequiredBackend
            # gating decisions without each plugin re-deriving it from scratch.
            $Global:HVConnectedBackends = $connectedBackends

            function Test-CategoryActive {
                param([string]$Category, [string[]]$Connected)
                # Only Initialize and Disconnect are sentinel categories that
                # always run. Everything else is gated on a connected backend.
                if ($Category -in @('00 Initialize','99 Disconnect','99 Cleanup')) { return $true }
                # 97 needs vCenter; Horizon REST is optional. With Horizon
                # connected, plugins auto-discover pool parents. Without it,
                # they fall back to the manual gold-image list from the
                # 'Pick Gold Images...' picker (or skip silently per-plugin).
                if ($Category -eq '97 vSphere for Horizon') { return ('vCenter' -in $Connected) }
                # 90 Gateways accepts either Horizon-side gateway listing or direct UAG admin
                if ($Category -eq '90 Gateways') { return ('Horizon' -in $Connected -or 'UAG' -in $Connected) }
                # Horizon-stack categories (DEM is part of the Horizon stack -
                # if you only picked vCenter, DEM does NOT fire)
                if ($Category -in @(
                    '10 Connection Servers','20 Cloud Pod Architecture','30 Desktop Pools',
                    '40 RDS Farms','50 Machines','60 Sessions','70 Events',
                    '80 Licensing and Certificates','92 Dynamic Environment Manager',
                    '93 Enrollment Server'
                )) {
                    return ('Horizon' -in $Connected)
                }
                # Single-backend categories
                if ($Category -eq '91 App Volumes') { return ('AppVolumes' -in $Connected) }
                if ($Category -eq '94 NSX')         { return ('NSX' -in $Connected) }
                if ($Category -eq '97 Nutanix Prism') { return ('Nutanix' -in $Connected) }
                if ($Category -eq 'B5 Workspace ONE Access') { return ('vIDM' -in $Connected) }
                if ($Category -eq 'B6 Workspace ONE UEM')    { return ('WS1UEM' -in $Connected) }
                if ($Category -in @('95 vSphere Backing Infra','96 vSphere Standalone','98 vSAN','99 vSphere Lifecycle','A0 Hardware')) {
                    return ('vCenter' -in $Connected)
                }
                return $true
            }

            $disabledSet = @{}
            foreach ($d in $disabledPlugins) { if ($d) { $disabledSet[$d] = $true } }
            $allFound = Get-ChildItem -Path (Join-Path $rootPath 'Plugins') -Recurse -Filter '*.ps1' |
                Where-Object { -not $_.PSIsContainer } | Sort-Object FullName

            $skippedCats = @{}
            $plugins = $allFound | Where-Object {
                $rel = $_.FullName.Substring((Join-Path $rootPath 'Plugins\').Length)
                if ($disabledSet.ContainsKey($rel)) { return $false }
                $cat = (Split-Path (Split-Path $_.FullName -Parent) -Leaf)
                if (-not (Test-CategoryActive -Category $cat -Connected $connectedBackends)) {
                    $skippedCats[$cat] = ($skippedCats[$cat] + 1)
                    return $false
                }
                return $true
            }

            Log "[+] Active scope: $(if ($connectedBackends) { $connectedBackends -join ', ' } else { 'NONE' })"
            if ($skippedCats.Count -gt 0) {
                $sk = ($skippedCats.Keys | Sort-Object | ForEach-Object { "$_ ($($skippedCats[$_]))" }) -join ', '
                Log "[i] Skipping out-of-scope categories: $sk"
            }
            $sync.PluginsTotal = $plugins.Count
            Log "[+] $($plugins.Count) plugin(s) in scope (out of $($allFound.Count) total)."

            $results = New-Object System.Collections.ArrayList

            # ---- ALWAYS inject a "Run Configuration" row showing what the
            # runspace actually received. Confirms whether the GUI's per-tab
            # values made it through. If a target was selected on the starter
            # but its Server FQDN was empty in the main GUI, you see it here.
            # Click-handler side values (captured BEFORE runspace launched)
            $clickHV  = if ($clickSnapshot) { $clickSnapshot.HVFqdnSnapshot }  else { '?' }
            $clickVC  = if ($clickSnapshot) { $clickSnapshot.VCFqdnSnapshot }  else { '?' }
            $clickAV  = if ($clickSnapshot) { $clickSnapshot.AVFqdnSnapshot }  else { '?' }
            $clickUAG = if ($clickSnapshot) { $clickSnapshot.UAGFqdnSnapshot } else { '?' }
            $clickNSX = if ($clickSnapshot) { $clickSnapshot.NSXFqdnSnapshot } else { '?' }
            # Readback values (proxy.GetVariable() called by click handler immediately after SetVariable)
            $rbHV  = if ($clickSnapshot) { $clickSnapshot.HVReadback }  else { '?' }
            $rbVC  = if ($clickSnapshot) { $clickSnapshot.VCReadback }  else { '?' }
            $rbAV  = if ($clickSnapshot) { $clickSnapshot.AVReadback }  else { '?' }
            $rbUAG = if ($clickSnapshot) { $clickSnapshot.UAGReadback } else { '?' }
            $rbNSX = if ($clickSnapshot) { $clickSnapshot.NSXReadback } else { '?' }
            $runCfg = @(
                [pscustomobject]@{ Target='Horizon';    ClickFQDN=$clickHV;  Readback=$rbHV;  RuntimeFQDN=$hvServer;  Username=if ($hvCredential) { $hvCredential.UserName } else { '(none)' };  Attempted=([bool]$hvServer);  Connected=([bool]$hvSession) }
                [pscustomobject]@{ Target='vCenter';    ClickFQDN=$clickVC;  Readback=$rbVC;  RuntimeFQDN=$vcServer;  Username=if ($vcCredential) { $vcCredential.UserName } else { '(none)' };  Attempted=([bool]$vcServer);  Connected=$vcConnected }
                [pscustomobject]@{ Target='AppVolumes'; ClickFQDN=$clickAV;  Readback=$rbAV;  RuntimeFQDN=$avServer;  Username=if ($avCredential) { $avCredential.UserName } else { '(none)' };  Attempted=([bool]$avServer);  Connected=([bool]$avSession) }
                [pscustomobject]@{ Target='UAG';        ClickFQDN=$clickUAG; Readback=$rbUAG; RuntimeFQDN=$uagServer; Username=if ($uagCredential) { $uagCredential.UserName } else { '(none)' }; Attempted=([bool]$uagServer); Connected=([bool]$uagSession) }
                [pscustomobject]@{ Target='NSX';        ClickFQDN=$clickNSX; Readback=$rbNSX; RuntimeFQDN=$nsxServer; Username=if ($nsxCredential) { $nsxCredential.UserName } else { '(none)' }; Attempted=([bool]$nsxServer); Connected=([bool]$nsxSession) }
            )
            # AD doesn't have a 'session' object (ActiveDirectory cmdlets
            # connect on each call). Count it as Attempted+Connected when the
            # tab populated $Global:ADServerFqdn AND the auto-discovery import
            # of the AD module succeeded.
            $adAttempted = [bool]($Global:ADServerFqdn)
            $adConnected = $adAttempted -and ([bool](Get-Module -Name ActiveDirectory))
            $runCfg += [pscustomobject]@{
                Target      = 'AD'
                ClickFQDN   = if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { '(none)' }
                Readback    = if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { '(none)' }
                RuntimeFQDN = if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { '' }
                Username    = if ($Global:ADCredential) { $Global:ADCredential.UserName } else { '(current Windows user)' }
                Attempted   = $adAttempted
                Connected   = $adConnected
            }
            $anySelected  = @($runCfg | Where-Object { $_.Attempted }).Count -gt 0
            $anyConnected = @($runCfg | Where-Object { $_.Connected }).Count -gt 0
            $cfgSeverity = if (-not $anySelected) { 'P1' } elseif (-not $anyConnected) { 'P1' } else { 'Info' }
            $cfgRec = if (-not $anySelected) {
                "NO BACKEND was actually attempted. Despite your starter-dialog selection, the runspace received empty Server FQDN values. Did you fill in the Server FQDN field on each selected tab in the main GUI? Re-run RunGUI.cmd, on each tab you ticked at the starter ALSO type the Server FQDN, Username, Password BEFORE clicking Run Health Check."
            } elseif (-not $anyConnected) {
                "Targets were attempted but NONE connected. See the 'Connection Attempts' row below for the explicit failure step (DNS / TCP / TLS / Auth) per target."
            } else { $null }
            $cfgAttempted = @($runCfg | Where-Object { $_.Attempted }).Count
            $cfgConnected = @($runCfg | Where-Object { $_.Connected }).Count
            $cfgHeader = "$cfgAttempted target(s) attempted, $cfgConnected connected"
            $null = $results.Add([pscustomobject]@{
                Plugin = '00 Run Configuration'
                Title  = 'Run Configuration'
                Header = $cfgHeader
                Comments = "ClickFQDN = what the GUI captured at click time. Readback = what proxy.GetVariable returned IMMEDIATELY after SetVariable (UI thread). RuntimeFQDN = what the runspace's $vcServer/etc. variable held when this row was built (runspace thread, much later). The three columns MUST match for a healthy run. ClickFQDN ok + Readback empty = SetVariable broken. Readback ok + RuntimeFQDN empty = the runspace clobbered the variable later (likely a module like PowerCLI shadowing it)."
                Display = 'Table'
                Author  = 'AuthorityGate'
                PluginVersion = 1.0
                PluginCategory = '00 Initialize'
                Severity = $cfgSeverity
                Recommendation = $cfgRec
                TableFormat = @{
                    ClickFQDN   = { param($v,$row) if (-not $v) { 'bad' } else { 'ok' } }
                    RuntimeFQDN = { param($v,$row)
                        if (-not $v -and $row.ClickFQDN) { 'bad' }   # GUI had it, runspace didn't = SetVariable bug
                        elseif (-not $v) { 'warn' }
                        else { 'ok' }
                    }
                    Attempted = { param($v,$row) if ($v -ne $true) { 'warn' } else { 'ok' } }
                    Connected = { param($v,$row) if ($v -ne $true) { 'bad' } else { 'ok' } }
                }
                Details = $runCfg
                Duration = 0; Error = $null
            })

            # ---- Inject the connection-attempts table as the FIRST plugin so
            # the report immediately tells the operator which backends came up
            # and which didn't, with the explicit step that failed (DNS / TCP
            # / TLS / Auth) plus the underlying exception text. Severity P1
            # if any selected backend failed.
            if ($connAttempts.Count -gt 0) {
                $anyFailed = @($connAttempts | Where-Object { $_.Result -ne 'Connected' }).Count -gt 0
                $null = $results.Add([pscustomobject]@{
                    Plugin = '00 Connection Attempts'
                    Title  = 'Connection Attempts'
                    Header = '[count] backend(s) attempted'
                    Comments = "Per-backend probe: DNS -> ICMP ping -> TCP -> TLS -> Auth. PingMs is roundtrip ms (-1 = ICMP blocked or host down). AltPorts shows other listening TCP ports on the same host so you can spot 'wrong port'. DiagCommands is paste-ready for deeper diagnosis."
                    Display = 'Table'
                    Author  = 'AuthorityGate'
                    PluginVersion = 1.0
                    PluginCategory = '00 Initialize'
                    Severity = if ($anyFailed) { 'P1' } else { 'Info' }
                    Recommendation = if ($anyFailed) { "Pin the failure step:`r`n  - DNSResolved=False -> FQDN wrong, or your DNS server doesn't know the internal name (VPN not connected? Wrong DNS suffix?). Run nslookup.`r`n  - TCPReachable=False with PingMs >= 0 -> host is alive but TCP port is dropped/closed. Causes: vCenter service stopped, vCenter listening on a different port (check the AltPorts column - 5480 = VAMI, 8443 = alt console), inbound ACL on the vCenter VM, source-IP allow-list, host-based firewall ON THE VCENTER VM, or AV on the runner host blocking the local socket.`r`n  - TCPReachable=False with PingMs = -1 -> host did NOT respond to ICMP either. VPN down, host powered off, routing broken, or upstream blocking.`r`n  - TLSHandshake=False -> server cert expired/invalid, server only allows TLS 1.0, or proxy/MITM in the path. Tick 'Skip cert validation' for labs.`r`n  - Result=Failed (TLS=True) -> credentials invalid; verify user/pass/domain.`r`n`r`nFor deeper diagnosis run the commands in the DiagCommands column from a PowerShell on this host." } else { $null }
                    TableFormat = @{
                        Result       = { param($v,$row) if ($v -ne 'Connected') { 'bad' } else { 'ok' } }
                        DNSResolved  = { param($v,$row) if ($v -ne $true) { 'bad' } else { 'ok' } }
                        TCPReachable = { param($v,$row) if ($v -ne $true) { 'bad' } else { 'ok' } }
                        TLSHandshake = { param($v,$row) if ($v -ne $true) { 'warn' } else { 'ok' } }
                        PingMs       = { param($v,$row) if ([int]$v -lt 0) { 'warn' } elseif ([int]$v -gt 200) { 'warn' } else { 'ok' } }
                    }
                    Details = $connAttempts.ToArray()
                    Duration = 0
                    Error = $null
                })
            }

            # Plugin loop. NOTE: variable names here use deliberately-unusual
            # prefixes (_pluginSw, _pluginErr) so dot-sourced plugins cannot
            # accidentally shadow them. Past breakage: a plugin assigning
            # $sw = $vDSwitchObject silently overwrote the runner's Stopwatch
            # and the next $sw.Stop() threw 'method Stop not found on
            # VmwareVDSwitchImpl'. Don't use bare $sw, $err, etc. in this loop.
            #
            # Multi-pod execution model:
            #   - Plugins under a "Horizon scope" category (00 Initialize, 10,
            #     20, 30, 40, 50, 60, 70, 80, 90, B0/B1/B2 because those depend
            #     on Horizon-side data) run ONCE per distinct POD. Multiple
            #     Connection Servers in the same pod are LDAP/ADAM-replicated
            #     and return identical data via the broker REST API, so
            #     iterating across them produces duplicate rows with the
            #     same content - which is what the user reported. We
            #     detect distinct pods via Get-HVPod (CPA federation
            #     listing) and only iterate when 2+ distinct pods exist.
            #   - All other plugins run ONCE (vCenter / AppVol / UAG / DEM /
            #     DNS / DHCP / AD / Cleanup). Multi-vCenter mode is handled
            #     by PowerCLI's $DefaultVIServers (cmdlets fan out
            #     automatically), not by an outer per-vCenter loop.
            $horizonScopedCategories = @(
                '00 Initialize','10 Connection Servers','20 Cloud Pod Architecture',
                '30 Desktop Pools','40 RDS Farms','50 Machines','60 Sessions',
                '70 Events','80 Licensing and Certificates','90 Gateways',
                'B0 Imprivata','B1 Identity Manager','B2 Multi-Factor Auth'
            )
            $nutanixScopedCategories = @('97 Nutanix Prism')
            # Defensive: if either session map is $null (not just empty),
            # fall back to a single-null-element array so the foreach below
            # always iterates at least once.
            if ($null -eq $hvSessions)   { $hvSessions   = @{} }
            if ($null -eq $ntnxSessions) { $ntnxSessions = @{} }

            # CPA distinct-pod detection. If 2+ Horizon CS FQDNs were entered,
            # they are USUALLY redundant replicas of one pod (typical multi-CS
            # HA pair). Only iterate per-CS when distinct pods are reported
            # by /v1/pods.
            #
            # v0.94.0 multi-pod consolidation fix:
            # On Horizon 8.6 /v1/pods returns empty objects (no id, no name)
            # for each connected CS, so the previous code keyed off
            # $localPod[0].id - which was empty - and dropped to the literal
            # 'unknown-pod' fallback. That correctly consolidated to ONE
            # iteration when ALL CSes returned empty. The regression was
            # subtler: Horizon 8.6 sometimes returns ONE empty object with
            # the connected CS's own id (the CS believes it IS the pod).
            # In that case each replica CS would yield its own id, the dict
            # would grow to 4 entries, and every plugin emitted 4 rows.
            #
            # The fix runs in two layers:
            #   1. Get-HVPod (in HorizonRest.psm1) now returns a synthesized
            #      single-pod row keyed off the connected CS server when
            #      /v1/pods gives only empty stub objects. The synth row
            #      carries _synthesized=true so we can detect this here.
            #   2. When stub-mode is detected on ANY CS, we COLLAPSE to a
            #      single iteration regardless of what id the synth produced
            #      because the entire REST surface is too thin to tell us
            #      whether the CSes are CPA peers or replica peers. Replicas
            #      consolidating to 1 is the correct default for a single
            #      typed-FQDN-list run.
            $podKeys = @()
            if ($hvSessions.Count -gt 1) {
                $distinctPods = @{}
                $anyStub = $false
                foreach ($csKey in $hvSessions.Keys) {
                    try {
                        Set-HVActiveSession -Server $csKey | Out-Null
                        if (Test-HVCSDataIsStub -Server $csKey) { $anyStub = $true }
                        $podList = @(Get-HVPod -ErrorAction SilentlyContinue)
                        $localPod = @($podList | Where-Object { $_.local_pod -eq $true -or $_.localPod -eq $true } | Select-Object -First 1)
                        if (-not $localPod -or @($localPod).Count -eq 0) { $localPod = @($podList | Select-Object -First 1) }
                        $podId = if ($localPod -and $localPod[0].id) { "$($localPod[0].id)" } else { 'unknown-pod' }
                        $isSynth = $false
                        if ($localPod -and $localPod[0] -and $localPod[0].PSObject.Properties['_synthesized']) {
                            $isSynth = ($localPod[0]._synthesized -eq $true)
                        }
                        if ($isSynth) { $anyStub = $true }
                        if (-not $distinctPods.ContainsKey($podId)) {
                            $distinctPods[$podId] = $csKey
                        }
                    } catch { }
                }
                # When the REST surface is stub-shaped, replica CSes look
                # like distinct pods because their identity comes from
                # synthesized server-fqdn keys. Collapse to one iteration
                # rather than running plugins N times against the same data.
                if ($anyStub) {
                    Log "[i] $($hvSessions.Count) Connection Server(s) detected; REST is stub-mode (no usable pod identity). Treating as single pod, plugins run once."
                } elseif ($distinctPods.Count -gt 1) {
                    $podKeys = @($distinctPods.Values)
                    Log "[i] Multi-pod (CPA) detected: $($distinctPods.Count) distinct pods. Plugins will iterate per pod."
                } else {
                    Log "[i] $($hvSessions.Count) Connection Server(s) detected, all in same pod. Plugins run once."
                }
                # Reset the module's active session to the first connected
                # CS so subsequent plugins (including any single-pass ones)
                # use a known-good session, not whichever one Set-HVActiveSession
                # last pointed at during the detection loop above.
                try { Set-HVActiveSession -Server (@($hvSessions.Keys)[0]) | Out-Null } catch { }
            } elseif ($hvSessions.Count -eq 1) {
                Log "[i] 1 Connection Server / single pod. Plugins run once."
            }
            if ($podKeys.Count -eq 0) { $podKeys = @($null) }

            $ntnxKeys = @()
            if ($ntnxSessions.Count -gt 0) { $ntnxKeys = @($ntnxSessions.Keys) }
            if ($ntnxKeys.Count -eq 0)     { $ntnxKeys = @($null) }

            foreach ($p in $plugins) {
                $pluginCat = (Split-Path (Split-Path $p.FullName -Parent) -Leaf)
                $isHorizonPlugin = ($horizonScopedCategories -contains $pluginCat)
                $isNutanixPlugin = ($nutanixScopedCategories -contains $pluginCat)
                # Default: single-pass with whichever default key is at the
                # head of the relevant array (likely $null when no session).
                $iterations = @($null)
                if ($isHorizonPlugin -and $podKeys.Count -gt 1) { $iterations = $podKeys }
                elseif ($isNutanixPlugin -and $ntnxKeys.Count -gt 1) { $iterations = $ntnxKeys }

                foreach ($podFqdn in $iterations) {
                    if ($isHorizonPlugin -and $podFqdn) {
                        try { Set-HVActiveSession -Server $podFqdn | Out-Null } catch { }
                    } elseif ($isNutanixPlugin -and $podFqdn) {
                        try { Set-NTNXActiveSession -Server $podFqdn | Out-Null } catch { }
                    }
                    $_pluginSw = [System.Diagnostics.Stopwatch]::StartNew()
                    $Title = $Header = $Comments = $Display = $Author = $Recommendation = $Severity = $null
                    $PluginVersion = 1.0
                    $PluginCategory = $pluginCat
                    # $RequiredBackend (Wave 4 / Theme D): plugin-declared list
                    # of backend names from $connectedBackends that MUST be
                    # connected for the plugin to run. When set and not all
                    # required backends are connected, the runner skips the
                    # plugin cleanly and emits a single 'skipped: backend not
                    # connected' Info row. This replaces the implicit silent-
                    # skip behavior where plugins for unconnected features
                    # produced empty rows the operator had to interpret.
                    $RequiredBackend = $null
                    $TableFormat = $null; $_pluginErr = $null; $details = @()
                    try { $details = @(. $p.FullName) } catch { $_pluginErr = $_.Exception.Message }
                    # Honor $RequiredBackend AFTER dot-source so the plugin's
                    # settings block can declare it. If declared, replace the
                    # plugin's emitted rows (if any) with a single skip row
                    # when the backend is missing.
                    if ($RequiredBackend) {
                        $reqList = @($RequiredBackend)
                        $missingBackends = @($reqList | Where-Object { $_ -notin $connectedBackends })
                        if ($missingBackends.Count -gt 0) {
                            $details = @([pscustomobject]@{
                                Plugin           = $p.BaseName
                                RequiredBackend  = ($reqList -join ', ')
                                MissingBackend   = ($missingBackends -join ', ')
                                Note             = "Skipped: this plugin requires $($missingBackends -join ', ') to be connected. Tick the target on the starter dialog and supply credentials on its tab to enable."
                            })
                            # Bump severity to Info so AGI's 0-finding suppression
                            # picks these up and they don't clutter operator-facing
                            # severity badges.
                            $Severity = 'Info'
                            if (-not $Header) { $Header = "Skipped (requires $($missingBackends -join ', '))" }
                        }
                    }
                    $_pluginSw.Stop(); $sync.PluginsDone++
                    $tag = if ($_pluginErr) { 'ERR' } else { "$(@($details).Count) item(s)" }
                    $podSuffix = ''
                    if ($isHorizonPlugin -and $podKeys.Count -gt 1 -and $podFqdn) { $podSuffix = " [pod=$podFqdn]" }
                    elseif ($isNutanixPlugin -and $ntnxKeys.Count -gt 1 -and $podFqdn) { $podSuffix = " [target=$podFqdn]" }
                    Log ("  > {0,-50}: {1} ({2:0.00}s){3}" -f $p.BaseName, $tag, $_pluginSw.Elapsed.TotalSeconds, $podSuffix)
                    if ($_pluginErr) {
                        $errSnip = if ($_pluginErr.Length -gt 220) { $_pluginErr.Substring(0,220) + '...' } else { $_pluginErr }
                        Log ("        ERR: $errSnip")
                    }
                    # Tag every row with its source Pod when running multi-pod
                    # so the report shows which pod produced which row.
                    if (($isHorizonPlugin -and $podKeys.Count -gt 1 -and $podFqdn) -or
                        ($isNutanixPlugin -and $ntnxKeys.Count -gt 1 -and $podFqdn)) {
                        $tagName = if ($isNutanixPlugin) { 'Target' } else { 'Pod' }
                        foreach ($d in @($details)) {
                            if ($d -is [pscustomobject] -or $d -is [psobject]) {
                                if (-not $d.PSObject.Properties[$tagName]) {
                                    Add-Member -InputObject $d -NotePropertyName $tagName -NotePropertyValue $podFqdn -Force
                                }
                            }
                        }
                    }
                    if (-not $Title)    { $Title    = $p.BaseName }
                    if (-not $Display)  { $Display  = 'Table' }
                    if (-not $Author)   { $Author   = 'AuthorityGate' }
                    if (-not $Severity) { $Severity = 'Info' }
                    # NOTE: variable named $_perPluginTitle (NOT $reportTitle)
                    # because PowerShell variable names are case-insensitive
                    # so $reportTitle would clobber the global $ReportTitle
                    # used by New-HVReport, making the report H1 read the
                    # last plugin's title instead of "Horizon Health Check".
                    $_perPluginTitle = $Title
                    if ($isHorizonPlugin -and $podKeys.Count -gt 1 -and $podFqdn) { $_perPluginTitle = "$Title (pod: $podFqdn)" }
                    elseif ($isNutanixPlugin -and $ntnxKeys.Count -gt 1 -and $podFqdn) { $_perPluginTitle = "$Title (target: $podFqdn)" }
                    $null = $results.Add([pscustomobject]@{
                        Plugin=$p.BaseName; Title=$_perPluginTitle; Header=$Header; Comments=$Comments
                        Display=$Display; Author=$Author; PluginVersion=$PluginVersion
                        PluginCategory=$PluginCategory; Severity=$Severity
                        Recommendation=$Recommendation; TableFormat=$TableFormat
                        Details=$details; Duration=$_pluginSw.Elapsed.TotalSeconds; Error=$_pluginErr
                        Pod=$podFqdn
                    })
                }
            }

            if ($hvSessions -and $hvSessions.Count -gt 0) { try { Disconnect-HVAllSessions } catch { } }
            elseif ($hvSession)  { try { Disconnect-HVRest } catch { } }
            if (Get-Command Disconnect-HVSoap -ErrorAction SilentlyContinue) { try { Disconnect-HVSoap } catch { } }
            if ($ntnxSessions -and $ntnxSessions.Count -gt 0) { try { Disconnect-NTNXAllSessions } catch { } }
            if ($vidmSession) { try { Disconnect-VIDMRest } catch { } }
            if ($uemSession)  { try { Disconnect-UEMRest } catch { } }
            if ($avSession)  { try { Disconnect-AVRest } catch { } }
            if ($uagSession) { try { Disconnect-UAGRest } catch { } }
            if ($nsxSession) { try { Disconnect-NSXRest } catch { } }
            if ($vcConnected) { try { Disconnect-VIServer -Server $vcServer -Confirm:$false -Force | Out-Null } catch { } }

            if (-not (Test-Path $outputPath)) { New-Item $outputPath -ItemType Directory -Force | Out-Null }
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $serverLabel = if ($hvServer) { $hvServer } elseif ($vcServer) { $vcServer } elseif ($avServer) { $avServer } elseif ($uagServer) { $uagServer } elseif ($nsxServer) { $nsxServer } else { 'unknown' }
            $safeSrv = $serverLabel -replace '[^a-zA-Z0-9.-]','_'

            # Build the connected-backend list for the report header
            $connected = @()
            if ($hvSession)   { $connected += "Horizon ($hvServer)" }
            if ($vcConnected) { $connected += "vCenter ($vcServer)" }
            if ($avSession)   { $connected += "App Volumes ($avServer)" }
            if ($uagSession)  { $connected += "UAG ($uagServer)" }
            if ($nsxSession)  { $connected += "NSX ($nsxServer)" }

            if ($genHtml) {
                $html = New-HVReport -Results $results.ToArray() -Server $serverLabel -Title $ReportTitle -ConnectedBackends $connected
                $reportFile = Join-Path $outputPath "HealthCheck-$safeSrv-$stamp.html"
                $html | Out-File -FilePath $reportFile -Encoding utf8
                Log "[+] HTML written: $reportFile"
                $sync.LastReport = $reportFile
            }

            # JSON sidecar - consumed by HealthCheckAGI for enriched reports.
            # Mirrors Invoke-HorizonHealthCheck.ps1's projection so both runners
            # produce identically-shaped JSON. TableFormat scriptblocks are
            # intentionally excluded - they do not survive ConvertTo-Json
            # cleanly and AGI does not consume them.
            $jsonFile = Join-Path $outputPath "HealthCheck-$safeSrv-$stamp.json"
            $jsonDoc = [pscustomobject]@{
                # Schema identifier intentionally NOT renamed in v0.94.1 -
                # HealthCheckAGI keys off this string. Bumping it (e.g. to
                # 'AuthorityGateHealthCheck/1') would force a coordinated
                # AGI release. Keep stable until the next schema-shape change.
                Schema = 'HorizonHealthCheck/1'
                Generated = (Get-Date).ToString('o')
                Server = $serverLabel
                Title = $ReportTitle
                CustomerName = $customerName
                ImageScanTier = if ($imageScanCred) { 'Tier2' } else { 'Tier1' }
                ConnectedBackends = $connected
                Results = $results.ToArray() | ForEach-Object {
                    # Scrub Details rows of non-primitive property values
                    # (PowerCLI ViewBase, COM, embedded .NET objects).
                    # ConvertTo-Json croaks with 'An item with the same key
                    # has already been added. Key: LinkedView' when a row
                    # holds a ViewBase reference whose property names
                    # collide case-insensitively (LinkedView / linkedView).
                    # Replace any non-trivial value with its ToString()
                    # representation so the row is JSON-safe.
                    $cleanedDetails = @()
                    if ($_.Details) {
                        foreach ($row in @($_.Details)) {
                            if ($null -eq $row) { continue }
                            if ($row -is [pscustomobject] -or $row -is [psobject]) {
                                $newRow = [ordered]@{}
                                foreach ($prop in $row.PSObject.Properties) {
                                    $val = $prop.Value
                                    # Primitives, strings, datetimes, bools,
                                    # numerics, and arrays-of-primitives serialize fine.
                                    if ($null -eq $val) { $newRow[$prop.Name] = $null; continue }
                                    if ($val -is [string] -or $val -is [bool] -or $val -is [int] -or
                                        $val -is [long] -or $val -is [double] -or $val -is [decimal] -or
                                        $val -is [datetime] -or $val -is [byte] -or $val -is [char]) {
                                        $newRow[$prop.Name] = $val
                                        continue
                                    }
                                    if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                                        # Convert each entry to string to avoid
                                        # surfacing ViewBase elements
                                        $newRow[$prop.Name] = @($val | ForEach-Object {
                                            if ($null -eq $_) { '' }
                                            elseif ($_ -is [string] -or $_ -is [int] -or $_ -is [bool] -or $_ -is [datetime]) { $_ }
                                            else { try { "$_" } catch { '(unprintable)' } }
                                        })
                                        continue
                                    }
                                    # Anything else (PowerCLI views, COM objects,
                                    # custom .NET): coerce to string.
                                    try { $newRow[$prop.Name] = "$val" } catch { $newRow[$prop.Name] = '(unprintable)' }
                                }
                                $cleanedDetails += [pscustomobject]$newRow
                            } else {
                                # Scalar Details entry - keep as-is if primitive, stringify otherwise
                                if ($row -is [string] -or $row -is [bool] -or $row -is [int]) { $cleanedDetails += $row }
                                else { try { $cleanedDetails += "$row" } catch { $cleanedDetails += '(unprintable)' } }
                            }
                        }
                    }
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
                        Details        = $cleanedDetails
                        Duration       = $_.Duration
                        Error          = $_.Error
                    }
                }
            }
            # Try the full Depth 12 serialization first. If it fails (a
            # plugin's Details rows can carry deeply-nested PowerCLI / COM
            # references that ConvertTo-Json chokes on), retry at Depth 6
            # without TableFormat or other complex shapes. NEVER leave a
            # 0-byte JSON file - that has bitten us before because the
            # pipeline pre-creates the file and ConvertTo-Json then throws.
            try {
                $jsonText = $jsonDoc | ConvertTo-Json -Depth 12 -ErrorAction Stop
                Set-Content -Path $jsonFile -Value $jsonText -Encoding utf8 -ErrorAction Stop
                Log "[+] JSON sidecar written: $jsonFile"
            } catch {
                Log "[!] JSON sidecar (Depth 12) failed: $($_.Exception.Message). Retrying Depth 6..."
                try {
                    $jsonText = $jsonDoc | ConvertTo-Json -Depth 6 -ErrorAction Stop
                    Set-Content -Path $jsonFile -Value $jsonText -Encoding utf8 -ErrorAction Stop
                    Log "[+] JSON sidecar (Depth 6 fallback) written: $jsonFile"
                } catch {
                    Log "[!] JSON sidecar Depth 6 also failed: $($_.Exception.Message). Writing minimal JSON shell so AGI does not see a 0-byte file."
                    try {
                        $minimal = [pscustomobject]@{
                            Schema = 'HorizonHealthCheck/1'
                            Generated = (Get-Date).ToString('o')
                            Server = $serverLabel
                            Title = $ReportTitle
                            CustomerName = $customerName
                            ConnectedBackends = $connected
                            ResultsError = "Full Results array failed to serialize: $($_.Exception.Message)"
                            ResultCount = @($results).Count
                        }
                        $minimal | ConvertTo-Json -Depth 4 | Set-Content -Path $jsonFile -Encoding utf8
                        Log "[+] Minimal JSON sidecar written: $jsonFile"
                    } catch {
                        Log "[!] Even minimal JSON write failed: $($_.Exception.Message)."
                    }
                }
            }

            if ($genWord) {
                Import-Module (Join-Path $rootPath 'Modules\WordReport.psm1') -Force
                $wordFile = Join-Path $outputPath "HealthCheck-$safeSrv-$stamp.docx"
                try {
                    New-HVWordReport -Results $results.ToArray() -Server $serverLabel -Title $ReportTitle `
                        -OutputFile $wordFile -Author $docAuthor -ConnectedBackends $connected -ShowWord:$showWord | Out-Null
                    Log "[+] Word document written: $wordFile"
                    if (-not $sync.LastReport) { $sync.LastReport = $wordFile }
                } catch { Log "[!] Word generation failed: $($_.Exception.Message)" }
            }
            Log "[+] Done."
        } catch {
            $sync.Error = $_.Exception.Message
            # Surface the script line + invocation context so future
            # "Cannot index into a null array" type crashes are
            # diagnosable without code archaeology.
            $loc = ''
            try {
                $ii = $_.InvocationInfo
                if ($ii) {
                    $loc = " [at $($ii.ScriptName):$($ii.ScriptLineNumber):$($ii.OffsetInLine)]"
                    if ($ii.Line) { $loc += " line: $($ii.Line.Trim())" }
                }
            } catch { }
            Log "[!] FATAL: $($_.Exception.Message)$loc"
        } finally {
            # Telemetry assembly MUST run on every code path - success, FATAL,
            # or empty-scope. Living inside the try-block previously meant any
            # mid-runspace exception silently dropped the run from the License
            # Portal dashboard. Bug B in the v0.93.65-onward telemetry gap.
            try {
                $tgts = @()
                if ($connAttempts) {
                    foreach ($row in @($connAttempts.ToArray())) {
                        if ($row.Result -eq 'Connected' -and $row.Target -and $row.Server) {
                            $tgts += @{ type = [string]$row.Target; fqdn = [string]$row.Server }
                        }
                    }
                }
                # AD has no Build-ConnRow / session object - it connects per-cmdlet.
                # An AD scope is active iff $Global:ADServerFqdn was populated
                # from the AD tab. Don't gate on Get-Module ActiveDirectory -
                # if a FATAL fired before any AD plugin imported the module,
                # the gate would suppress the telemetry row even though the
                # operator clearly selected AD. The dashboard is allowed to
                # show "AD attempted but plugin loop didn't reach it".
                if ($Global:ADServerFqdn) {
                    $tgts += @{ type = 'AD'; fqdn = [string]$Global:ADServerFqdn }
                }
                $sev = @{ P1=0; P2=0; P3=0; Info=0 }
                if ($results) {
                    foreach ($r in $results) {
                        $key = if ($r.Severity) { [string]$r.Severity } else { 'Info' }
                        if (-not $sev.ContainsKey($key)) { $sev[$key] = 0 }
                        $sev[$key] = $sev[$key] + 1
                    }
                }
                $completedAt = Get-Date
                $duration    = if ($runStartedAt) { [int]($completedAt - $runStartedAt).TotalSeconds } else { 0 }
                $runStatus   = if ($sync.Error) { 'failed' } else { 'completed' }
                $tlfp = if ($machineFp) { $machineFp.Substring(0, [Math]::Min(16, $machineFp.Length)) } else { '(no fp)' }
                Log "[*] Telemetry assembled (status=$runStatus): run_id=$runId, fp=$tlfp..., targets=$($tgts.Count), findings=P1:$($sev.P1)/P2:$($sev.P2)/P3:$($sev.P3)/Info:$($sev.Info)"
                $sync.TelemetryPayload = @{
                    run_id              = $runId
                    machine_fp          = $machineFp
                    hostname            = $env:COMPUTERNAME
                    tool_version        = "$runspaceVersion"
                    started_at          = if ($runStartedAt) { [int]([DateTimeOffset]$runStartedAt).ToUnixTimeSeconds() } else { 0 }
                    completed_at        = [int]([DateTimeOffset]$completedAt).ToUnixTimeSeconds()
                    duration_seconds    = $duration
                    doc_author          = $docAuthor
                    customer_engagement = $customerName
                    targets             = $tgts
                    plugin_count_total  = if ($plugins) { [int]$plugins.Count } else { 0 }
                    plugin_count_executed = [int]$sync.PluginsDone
                    findings_summary    = $sev
                    report_filename     = if ($sync.LastReport) { Split-Path -Leaf $sync.LastReport } else { '' }
                    report_size_bytes   = if ($sync.LastReport -and (Test-Path $sync.LastReport)) { (Get-Item $sync.LastReport).Length } else { 0 }
                    status              = $runStatus
                }
            } catch {
                Log "[!] Telemetry payload assembly failed: $($_.Exception.Message)"
            }
            # Done flag is intentionally NOT set here. The cleanup tick on
            # the UI thread sets $sync.Done = $true AFTER it logs the
            # telemetry submission result, so the logTimer keeps draining
            # long enough for those lines to reach the visible textbox.
        }
    })

    $handle = $ps.BeginInvoke()
    $cleanup = New-Object System.Windows.Forms.Timer
    $cleanup.Interval = 500
    # GetNewClosure captures $handle, $ps, $rs, $cleanup, $sync at scriptblock
    # creation time. WITHOUT it, the timer's tick body uses dynamic scoping
    # at fire time and these locals appear as $null - $null.IsCompleted is
    # falsy in non-strict mode, so the body would never execute and
    # telemetry submission would be silently skipped.
    $cleanup.Add_Tick({
        try {
            if (-not $handle -or -not $handle.IsCompleted) { return }
            try { $ps.EndInvoke($handle) } catch { }
            try { $ps.Dispose() }      catch { }
            try { $rs.Dispose() }      catch { }
            try { $cleanup.Stop() }    catch { }
            try { $cleanup.Dispose() } catch { }

            # Silent telemetry submission. Success goes to the dashboard;
            # transient failures auto-queue locally and retry on the next
            # run via Submit-AGUsageQueue. Operators who need an explicit
            # success/fail readout use the "Test Telemetry Now" button on
            # the License tab. The visible run log intentionally ends with
            # the "Telemetry assembled" line to keep operator output clean.
            try {
                if ($sync -and $sync.TelemetryPayload) {
                    [void](Submit-AGUsageEvent -Payload $sync.TelemetryPayload)
                }
            } catch { }
        } catch {
            try { Write-Host "[!] cleanup tick swallowed: $($_.Exception.Message)" -ForegroundColor DarkYellow } catch { }
        } finally {
            if ($sync) { try { $sync.Done = $true } catch { } }
        }
    }.GetNewClosure())
    $cleanup.Start()
})

$btnOpen.Add_Click({ if ($sync.LastReport -and (Test-Path $sync.LastReport)) { Start-Process $sync.LastReport } })

$form.Add_FormClosing({ Save-State })
[void]$form.ShowDialog()
