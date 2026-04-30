# Start of Settings
# End of Settings

$Title          = 'Pool USB / Drive Redirection'
$Header         = 'Pool USB redirection settings'
$Comments       = 'USB redirection is a major data-exfil channel. Default-deny unless business-justified.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '30 Desktop Pools'
$Severity       = 'P2'
$Recommendation = 'Settings -> Global Settings or per-pool: disable USB redirection or apply USB filter.'

if (-not (Get-HVRestSession)) { return }
try { $g = Get-HVGlobalSettings } catch { return }
if (-not $g) { return }
[pscustomobject]@{
    DisableUSBRedirection      = $g.disable_usb_redirection
    DisableClipboardRedirection = $g.disable_clipboard_redirection
    DisableDriveRedirection    = $g.disable_drive_redirection
    DisableSmartCardRedirection = $g.disable_smart_card_redirection
}
