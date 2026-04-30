# Start of Settings
# End of Settings

$Title          = "UAG Authentication Methods Detail"
$Header         = "UAG-side auth method configuration"
$Comments       = "Per-method auth configuration on the UAG itself: SAML IdP / SP, RADIUS server, Cert auth root CAs, RSA SecurID, OAuth. Each method must align with the corresponding Horizon-side authenticator OR the auth flow breaks at the UAG and the Horizon Console reports 'broker-side' failure."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "90 Gateways"
$Severity       = "Info"
$Recommendation = "Verify SAML metadata URL still reachable. RADIUS shared secret rotated within last 12 months. Cert-auth chain includes intermediates."

if (-not (Get-UAGRestSession)) { return }
$rows = @()
try { $saml = Get-UAGSAMLIdpSettings } catch { }
try { $sp   = Get-UAGSAMLServiceProvider } catch { }
try { $rad  = Get-UAGRADIUSSettings } catch { }
try { $crt  = Get-UAGCertAuthSettings } catch { }
try { $sec  = Get-UAGRSASecurID } catch { }
try { $oa   = Get-UAGOAuthSettings } catch { }

if ($saml) {
    foreach ($s in @($saml)) {
        $rows += [pscustomobject]@{
            Method='SAML-IdP'; Name=$s.entityID; Detail=$s.metadataXML.Length.ToString() + ' bytes XML'; Endpoint=$s.metadataURL; Enabled=[bool]$s.enabled
        }
    }
}
if ($sp)   { $rows += [pscustomobject]@{ Method='SAML-SP';      Name=$sp.entityID;          Detail='ACS=' + $sp.acsUrl;            Endpoint=$sp.metadataURL;           Enabled=[bool]$sp.enabled } }
if ($rad)  { $rows += [pscustomobject]@{ Method='RADIUS';       Name=$rad.displayName;      Detail="Primary=$($rad.hostName)";    Endpoint="$($rad.hostName):$($rad.authPort)"; Enabled=[bool]$rad.enabled } }
if ($crt)  { $rows += [pscustomobject]@{ Method='Certificate';  Name=$crt.displayName;      Detail='RootCAs=' + @($crt.certificateChain).Count; Endpoint=''; Enabled=[bool]$crt.enabled } }
if ($sec)  { $rows += [pscustomobject]@{ Method='RSA-SecurID';  Name=$sec.displayName;      Detail=$sec.serverHost; Endpoint=$sec.serverHost; Enabled=[bool]$sec.enabled } }
if ($oa)   { $rows += [pscustomobject]@{ Method='OAuth';        Name=$oa.displayName;       Detail=$oa.tokenEndpoint; Endpoint=$oa.tokenEndpoint; Enabled=[bool]$oa.enabled } }

if (-not $rows -or $rows.Count -eq 0) {
    [pscustomobject]@{ Note = 'No auth methods configured directly on UAG (likely all auth handled by Horizon broker upstream).' }
    return
}
$rows

$TableFormat = @{ Enabled = { param($v,$row) if ($v -eq $true) { 'ok' } else { 'warn' } } }
