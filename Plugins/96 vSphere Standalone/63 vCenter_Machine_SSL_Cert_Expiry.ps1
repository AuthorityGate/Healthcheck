# Start of Settings
$WarnDays = 60
$BadDays  = 30
# End of Settings

$Title          = 'vCenter Machine SSL Certificate Expiry'
$Header         = '[count] cert chain entry(ies) expiring soon'
$Comments       = "vCenter machine SSL is the certificate clients see when they connect to the vCenter UI / API. Distinct from STS (auth signing) and Solution User (back-end auth) certs. Default lifetime varies by install age; check at least quarterly."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P2'
$Recommendation = 'Renew via /usr/lib/vmware-vmca/bin/certificate-manager option 3 (regen machine SSL with VMCA-issued cert) or option 1 (replace with custom CA-signed). Restart vCenter services after rotation.'

if (-not $Global:VCConnected) { return }

$servers = @($global:DefaultVIServers | Where-Object { $_ -and $_.IsConnected })
if ($servers.Count -eq 0 -and $Global:VCServer) { $servers = @([pscustomobject]@{ Name = $Global:VCServer }) }
foreach ($srv in $servers) {
    $hostName = $srv.Name
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($hostName, 443, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(5000)) { $tcp.Close(); throw "Connect to $hostName`:443 timed out after 5s" }
        $tcp.EndConnect($iar)
        $stream = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, ({$true} -as [System.Net.Security.RemoteCertificateValidationCallback]))
        $stream.AuthenticateAsClient($hostName)
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $stream.RemoteCertificate
        $stream.Close(); $tcp.Close()
        $daysLeft = ($cert.NotAfter - (Get-Date)).Days
        [pscustomobject]@{
            VCenter    = $hostName
            Subject    = $cert.Subject
            Issuer     = $cert.Issuer
            NotBefore  = $cert.NotBefore
            NotAfter   = $cert.NotAfter
            DaysLeft   = $daysLeft
            Thumbprint = $cert.Thumbprint
        }
    } catch {
        [pscustomobject]@{
            VCenter   = $hostName; Subject=''; Issuer=''; NotBefore=$null; NotAfter=$null
            DaysLeft  = -1
            Thumbprint = "ERROR: $($_.Exception.Message)"
        }
    }
}

$TableFormat = @{
    DaysLeft = { param($v,$row) if ([int]$v -lt $BadDays) { 'bad' } elseif ([int]$v -lt $WarnDays) { 'warn' } else { '' } }
}
