# Start of Settings
$MinBannerChars = 30
# End of Settings

$Title          = 'ESXi Login Banner / Welcome Message'
$Header         = '[count] host(s) with empty or stub login banner'
$Comments       = "vSCG: Annotations.WelcomeMessage (DCUI) and Config.Etc.issue (SSH) should both contain a legal-cover banner that names the company, asserts authorized-use-only, and warns against unauthorized access. Empty/short banners weaken legal posture."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P3'
$Recommendation = "Set Annotations.WelcomeMessage to your standard legal banner. Apply via host profile so all hosts inherit a consistent message. Banner length >= $MinBannerChars chars."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $banner = (Get-AdvancedSetting -Entity $h -Name 'Annotations.WelcomeMessage' -ErrorAction SilentlyContinue).Value
    $issue  = $null
    if (-not $banner) { $issue = 'WelcomeMessage empty' }
    elseif ([string]$banner.Length -lt $MinBannerChars) { $issue = "WelcomeMessage too short ($([string]$banner.Length) chars)" }
    if ($issue) {
        [pscustomobject]@{
            Host          = $h.Name
            WelcomeLength = [string]$banner.Length
            Issue         = $issue
            Preview       = if ($banner) { ($banner.Substring(0,[Math]::Min(60,$banner.Length))) } else { '(empty)' }
        }
    }
}
