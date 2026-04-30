# Start of Settings
# End of Settings

$Title          = 'DEM Folder Redirection Inventory'
$Header         = 'Folder redirection configs'
$Comments       = 'Folder redirection moves user folders to network. Mis-set redirection causes Office signature loss / Outlook OST corruption.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P2'
$Recommendation = 'Limit redirection to Documents, Desktop, Pictures. Avoid redirecting AppData unless required for compliance.'

$share = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware UEM\Agent\FlexEngine' -ErrorAction SilentlyContinue).ConfigShare
if (-not $share -or -not (Test-Path $share)) { return }
$cfg = Get-ChildItem -Path (Join-Path $share 'FolderRedirection') -Recurse -ErrorAction SilentlyContinue
if (-not $cfg) { return }
[pscustomobject]@{ FolderRedirectionConfigs = $cfg.Count }
