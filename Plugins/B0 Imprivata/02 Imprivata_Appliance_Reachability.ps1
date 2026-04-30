# Start of Settings
# Imprivata appliance(s) - operator hint via $Global:ImprivataApplianceList = @('https://imprivata.lab.local')
# End of Settings

$Title          = 'Imprivata Appliance Reachability'
$Header         = "[count] Imprivata appliance(s) checked"
$Comments       = "From any reachable network point (the runner machine), test TCP + TLS to each known Imprivata Appliance URL. Imprivata authentication depends on the appliance being reachable from every CS / desktop / kiosk."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'B0 Imprivata'
$Severity       = 'P1'
$Recommendation = "Imprivata appliance unreachable = SSO + tap-and-go broken for the affected scope. Verify firewall, DNS, cert validity. Imprivata appliances expose a healthcheck endpoint for monitoring integration."

if (-not (Test-Path Variable:Global:ImprivataApplianceList)) {
    [pscustomobject]@{
        Appliance = '(no Imprivata appliances configured)'
        Tcp443 = ''; Tls = ''; CertExpiry = ''
        Note = 'Set $Global:ImprivataApplianceList = @("https://imprivata.fqdn") in the runner before invoking, OR the GUI per-engagement.'
    }
    return
}

foreach ($url in @($Global:ImprivataApplianceList)) {
    if (-not $url) { continue }
    $row = [pscustomobject]@{
        Appliance = $url
        Tcp443 = ''
        Tls = ''
        CertExpiry = ''
        CertSubject = ''
        Note = ''
    }

    try {
        $u = [System.Uri]$url
        $host = $u.Host
        $port = if ($u.Port -gt 0) { $u.Port } else { 443 }

        # TCP probe
        $tcp = New-Object System.Net.Sockets.TcpClient
        $async = $tcp.BeginConnect($host, $port, $null, $null)
        $ok = $async.AsyncWaitHandle.WaitOne(3000, $false)
        if ($ok -and $tcp.Connected) {
            $row.Tcp443 = 'OK'
            # TLS handshake + cert read
            try {
                $stream = $tcp.GetStream()
                $ssl = New-Object System.Net.Security.SslStream($stream, $false, ({ $true } -as [System.Net.Security.RemoteCertificateValidationCallback]))
                $ssl.AuthenticateAsClient($host)
                $cert = $ssl.RemoteCertificate
                if ($cert) {
                    $row.Tls = $ssl.SslProtocol.ToString()
                    $row.CertSubject = $cert.Subject
                    $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)
                    $daysLeft = [int]($cert2.NotAfter - (Get-Date)).TotalDays
                    $row.CertExpiry = "{0:yyyy-MM-dd} ({1} days)" -f $cert2.NotAfter, $daysLeft
                    if ($daysLeft -lt 60) { $row.Note = "Cert expires soon ($daysLeft days)." }
                }
                $ssl.Close()
            } catch { $row.Tls = "Failed: $($_.Exception.Message)" }
        } else {
            $row.Tcp443 = "FAIL"
            $row.Note = "TCP $port not reachable from runner host."
        }
        $tcp.Close()
    } catch {
        $row.Tcp443 = "ERROR: $($_.Exception.Message)"
    }
    $row
}

$TableFormat = @{
    Tcp443 = { param($v,$row) if ($v -match 'FAIL|ERROR') { 'bad' } elseif ($v -eq 'OK') { '' } else { 'warn' } }
}
