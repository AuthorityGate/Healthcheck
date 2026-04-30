<#
    GlobalVariables.ps1
    Defaults for the CLI runner. Override values inline or pass parameters
    to Invoke-HorizonHealthCheck.ps1. Per-plugin tunables live at the top
    of each plugin file (between '# Start of Settings' and '# End of Settings').

    IMPORTANT: every default is wrapped in 'if (-not $X)' so dot-sourcing
    this file does NOT clobber a value already set in the calling scope
    (e.g. the GUI runspace sets vcServer via SessionStateProxy.SetVariable
    BEFORE this file runs). Plain '$X = ""' would silently wipe it because
    PowerShell variable names are case-insensitive ('$VCServer' and
    '$vcServer' are the same variable).
#>

# ---- Connection ------------------------------------------------------------
if (-not $HVServer)               { $HVServer = '' }                  # e.g. 'cs1.corp.example.com'
if (-not $HVDomain)               { $HVDomain = '' }                  # NetBIOS or DNS domain
if (-not (Test-Path Variable:HVSkipCertificateCheck)) { $HVSkipCertificateCheck = $false }

if (-not $VCServer)               { $VCServer = '' }
if (-not (Test-Path Variable:VCSkipCertificateCheck)) { $VCSkipCertificateCheck = $false }

# ---- Output ----------------------------------------------------------------
if (-not $ReportPath)             { $ReportPath  = Join-Path $PSScriptRoot 'Reports' }
if (-not $ReportTitle)            { $ReportTitle = 'Horizon Health Check' }

# ---- Email (optional) ------------------------------------------------------
if (-not (Test-Path Variable:SendEmail))  { $SendEmail  = $false }
if (-not $SmtpServer)             { $SmtpServer = '' }
if (-not $SmtpPort)               { $SmtpPort   = 25 }
if (-not (Test-Path Variable:SmtpUseSsl)) { $SmtpUseSsl = $false }
if (-not $EmailFrom)              { $EmailFrom  = '' }
if (-not $EmailTo)                { $EmailTo    = @() }
if (-not $EmailSubject)           { $EmailSubject = 'Horizon Health Check - {0:yyyy-MM-dd}' }

# ---- Severity model --------------------------------------------------------
# P1 = critical (immediate)
# P2 = high    (next maintenance)
# P3 = medium  (planned)
# Info = informational, no action required
