# Start of Settings
# Operator hint: $Global:OCSPUrlList = @('http://ocsp.corp.local')
#                $Global:CDPUrlList  = @('http://pki.corp.local/CertEnroll/RootCA.crl')
# End of Settings

$Title          = "OCSP / CDP / AIA Reachability"
$Header         = "PKI revocation + chain endpoint probe"
$Comments       = "OCSP responder + CRL distribution point + Authority Information Access URL probes. If any are unreachable, smart-card / SAML / TrueSSO can fail with revocation-check timeouts. Auto-discovers from a sample certificate when the lists are not pre-populated."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B9 Certificate Authority"
$Severity       = "P1"
$Recommendation = "OCSP / CDP / AIA URLs MUST be reachable from every machine that does revocation checking (UAG, Connection Server, Enrollment Server, end-user VDIs). Offline-Root-CA CRL must be republished and distributed to every Subordinate CA's CDP location at least quarterly."

$urls = @()
if ($Global:OCSPUrlList) { foreach ($u in $Global:OCSPUrlList) { $urls += [pscustomobject]@{ Type='OCSP'; Url=$u } } }
if ($Global:CDPUrlList)  { foreach ($u in $Global:CDPUrlList)  { $urls += [pscustomobject]@{ Type='CDP';  Url=$u } } }
if ($Global:AIAUrlList)  { foreach ($u in $Global:AIAUrlList)  { $urls += [pscustomobject]@{ Type='AIA';  Url=$u } } }

# Auto-discover from a Connection Server cert if no list supplied and Horizon is connected
if ($urls.Count -eq 0 -and $Global:HVSession) {
    try {
        $cs = Get-HVConnectionServer
        if ($cs -and $cs[0].name) {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect($cs[0].name, 443)
            $stream = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, ({$true} -as [System.Net.Security.RemoteCertificateValidationCallback]))
            $stream.AuthenticateAsClient($cs[0].name)
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($stream.RemoteCertificate)
            $stream.Close(); $tcp.Close()
            foreach ($ext in $cert.Extensions) {
                if ($ext.Oid.Value -eq '1.3.6.1.5.5.7.1.1') { # AIA
                    $aiaText = $ext.Format($false)
                    if ($aiaText -match 'http[^,]+') { $urls += [pscustomobject]@{ Type='AIA'; Url=$Matches[0] } }
                }
                if ($ext.Oid.Value -eq '2.5.29.31') { # CRL Distribution Points
                    $cdpText = $ext.Format($false)
                    if ($cdpText -match 'http[^,]+') { $urls += [pscustomobject]@{ Type='CDP'; Url=$Matches[0] } }
                }
            }
        }
    } catch { }
}

if ($urls.Count -eq 0) {
    [pscustomobject]@{ Note = 'No OCSP/CDP/AIA URLs to probe. Set $Global:OCSPUrlList / CDPUrlList / AIAUrlList, OR ensure Horizon is connected for auto-discovery.' }
    return
}

foreach ($u in $urls) {
    $row = [pscustomobject]@{
        Type        = $u.Type
        Url         = $u.Url
        Reachable   = $false
        ResponseMs  = ''
        StatusCode  = ''
        SizeBytes   = ''
        Note        = ''
    }
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $resp = Invoke-WebRequest -Uri $u.Url -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        $sw.Stop()
        $row.Reachable = $true
        $row.ResponseMs = $sw.ElapsedMilliseconds
        $row.StatusCode = [int]$resp.StatusCode
        $row.SizeBytes  = $resp.RawContentLength
    } catch {
        $row.Note = $_.Exception.Message
    }
    $row
}

$TableFormat = @{
    Reachable = { param($v,$row) if ($v -eq $true) { 'ok' } else { 'bad' } }
    ResponseMs = { param($v,$row) if ([int]"$v" -gt 2000) { 'warn' } else { '' } }
}
