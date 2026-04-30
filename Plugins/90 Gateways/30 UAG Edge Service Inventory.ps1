# Start of Settings
# End of Settings

$Title          = "UAG Edge Service Inventory"
$Header         = "[count] edge service definition(s) on UAG"
$Comments       = "Every Edge Service configured on the UAG: View (Horizon broker), Web Reverse Proxy, Tunnel, Content Gateway. Surfaces target hosts, auth method, edge-service version, and enabled state. Edge Services are how UAG knows what backend to proxy."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "90 Gateways"
$Severity       = "Info"
$Recommendation = "Disabled / orphaned edge services should be removed. Backend hosts that don't resolve are misconfigurations. Auth method should match the Horizon-side authenticator (RADIUS / SAML / SC)."

if (-not (Get-UAGRestSession)) { return }
$rows = @()
try { $view = Get-UAGEdgeViewService;        if ($view)    { $rows += [pscustomobject]@{ Service='View';            Enabled=[bool]$view.enabled;    Backend=$view.proxyDestinationUrl;     AuthMethod=$view.authMethods;    Detail=$view.tunnelExternalUrl } } } catch { }
try { $wrp  = Get-UAGEdgeWebReverseProxy;    if ($wrp)     { foreach ($w in @($wrp))     { $rows += [pscustomobject]@{ Service='WebReverseProxy'; Enabled=[bool]$w.enabled;       Backend=$w.proxyDestinationUrl;        AuthMethod=$w.authMethods;       Detail=$w.proxyHostPattern } } } } catch { }
try { $tun  = Get-UAGEdgeTunnelService;      if ($tun)     { $rows += [pscustomobject]@{ Service='Tunnel';          Enabled=[bool]$tun.enabled;     Backend=$tun.proxyDestinationUrl;      AuthMethod='';                   Detail=$tun.tunnelExternalUrl } } } catch { }
try { $cgw  = Get-UAGEdgeContentGw;          if ($cgw)     { $rows += [pscustomobject]@{ Service='ContentGateway';   Enabled=[bool]$cgw.enabled;     Backend=$cgw.proxyDestinationUrl;      AuthMethod=$cgw.authMethods;     Detail=$cgw.contentHost } } } catch { }
if (-not $rows -or $rows.Count -eq 0) {
    [pscustomobject]@{ Note = 'No edge services returned by /config/edgeservice/*. Likely an unauthenticated mode or older UAG build.' }
    return
}
$rows

$TableFormat = @{ Enabled = { param($v,$row) if ($v -eq $true) { 'ok' } else { 'warn' } } }
