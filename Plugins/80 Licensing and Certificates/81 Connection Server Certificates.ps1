# Start of Settings
# Warn if any CS or vCenter certificate expires within this many days.
$CertWarnDays = 60
# End of Settings

$Title          = "Connection Server Certificates Expiring"
$Header         = "[count] certificate(s) expiring in $CertWarnDays days or less"
$Comments       = @"
Validates each Connection Server's TLS certificate via two paths:

1. Horizon REST first (NO network probe needed): /v1/monitor/connection-servers returns certificate metadata - subject, issuer, NotAfter, valid flag - if the calling user has 'Inventory Administrators' rights. This is the most reliable source.

2. Direct TCP/443 probe as fallback: opens a TLS handshake to the CS FQDN and reads the live cert. Fails if the runner can't resolve / reach the CS, OR if the CS REST didn't expose a hostname under any expected field name.

Self-signed or expired certs break Horizon Console + UAG trust.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = "80 Licensing and Certificates"
$Severity       = "P1"
$Recommendation = "Re-issue cert from the internal PKI / public CA, install via 'Certificates' MMC -> Personal -> 'vdm' friendly-name, restart 'VMware Horizon Connection Server'."

$cs = @(Get-HVConnectionServer)
if ($cs.Count -eq 0) { return }

# Helper: walk dotted property paths and return the first non-empty match.
function Get-CSValue {
    param($Item, [string[]]$Paths)
    foreach ($p in $Paths) {
        $segs = $p -split '\.'
        $cur = $Item; $ok = $true
        foreach ($s in $segs) { if ($null -eq $cur) { $ok=$false; break } ; try { $cur = $cur.$s } catch { $ok=$false; break } ; if ($null -eq $cur) { $ok=$false; break } }
        if ($ok -and $cur) { return $cur }
    }
    return $null
}

$certResults = foreach ($c in $cs) {
    # Resolve a usable hostname from any of the schema variants.
    $hostName = Get-CSValue -Item $c -Paths @(
        'name','display_name','dns_name','host_name','hostname','server_name','fqdn'
    )

    # Path 1: read cert metadata directly from the Horizon REST response.
    # 2206+ exposes `certificate` as a sub-object with subject/issuer/valid/
    # not_after fields. After ConvertTo-HVFlat lifts them up, we can also
    # find them at the top level.
    $apiSubject = Get-CSValue -Item $c -Paths @(
        'certificate.subject','certificate.subject_name','subject','certificate_subject'
    )
    $apiIssuer  = Get-CSValue -Item $c -Paths @(
        'certificate.issuer','certificate.issuer_name','issuer','certificate_issuer'
    )
    $apiNotAfter = Get-CSValue -Item $c -Paths @(
        'certificate.not_after','certificate.expires_on','certificate.expiration','not_after','expiration_date','certificate_expiry'
    )
    $apiValid = Get-CSValue -Item $c -Paths @(
        'certificate.valid','certificate.is_valid','certificate_valid'
    )

    if ($apiSubject -or $apiIssuer -or $apiNotAfter) {
        # Use API-side cert info. Convert NotAfter (which may be a unix
        # ms timestamp or ISO 8601 string) to a [datetime] for the Days
        # calculation.
        $na = $null; $daysLeft = $null
        if ($apiNotAfter) {
            try {
                if ($apiNotAfter -match '^\d{10,13}$') {
                    $ms = [int64]$apiNotAfter
                    if ($ms -gt 1000000000000) { $na = (Get-Date '1970-01-01').AddMilliseconds($ms) }
                    else { $na = (Get-Date '1970-01-01').AddSeconds($ms) }
                } else {
                    $na = [datetime]$apiNotAfter
                }
                $daysLeft = [int]($na - (Get-Date)).TotalDays
            } catch { }
        }
        $self = if ($apiSubject -and $apiIssuer) { ([string]$apiSubject -eq [string]$apiIssuer) } else { $null }
        [pscustomobject]@{
            Host       = if ($hostName) { $hostName } else { '(name missing in REST response)' }
            Source     = 'Horizon REST'
            Subject    = $apiSubject
            Issuer     = $apiIssuer
            NotAfter   = $na
            DaysLeft   = if ($null -ne $daysLeft) { $daysLeft } else { '' }
            Thumbprint = ''
            Valid      = $apiValid
            SelfSigned = $self
        }
        continue
    }

    # Path 2: fall back to direct TCP/443 probe. Skip if no hostname.
    if (-not $hostName) {
        [pscustomobject]@{
            Host       = '(name missing in REST response)'
            Source     = 'skipped'
            Subject    = "Service account may lack 'Inventory Administrators' role - cert metadata not exposed AND no hostname for fallback probe"
            Issuer     = ''
            NotAfter   = $null
            DaysLeft   = ''
            Thumbprint = ''
            Valid      = ''
            SelfSigned = $null
        }
        continue
    }

    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.ReceiveTimeout = 5000
        $iar = $tcp.BeginConnect([string]$hostName, 443, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(5000)) {
            $tcp.Close()
            throw "Connect timed out after 5s"
        }
        $tcp.EndConnect($iar)
        $stream = $tcp.GetStream()
        $ssl = New-Object System.Net.Security.SslStream($stream, $false, ({$true} -as [System.Net.Security.RemoteCertificateValidationCallback]))
        $ssl.AuthenticateAsClient([string]$hostName)
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
        $daysLeft = [int]($cert.NotAfter - (Get-Date)).TotalDays
        [pscustomobject]@{
            Host       = $hostName
            Source     = 'TCP/443 probe'
            Subject    = $cert.Subject
            Issuer     = $cert.Issuer
            NotAfter   = $cert.NotAfter
            DaysLeft   = $daysLeft
            Thumbprint = $cert.Thumbprint
            Valid      = $true
            SelfSigned = ($cert.Subject -eq $cert.Issuer)
        }
        $ssl.Close(); $tcp.Close()
    } catch {
        [pscustomobject]@{
            Host       = $hostName
            Source     = 'TCP/443 probe (failed)'
            Subject    = '(unreachable: ' + $_.Exception.Message + ')'
            Issuer     = ''
            NotAfter   = $null
            DaysLeft   = ''
            Thumbprint = ''
            Valid      = $false
            SelfSigned = $null
        }
    }
}

# Filter: only keep certs that need attention - expired, near-expiry, or
# self-signed. Skip rows where DaysLeft is empty (couldn't be measured).
$certResults | Where-Object {
    ($_.DaysLeft -is [int] -and $_.DaysLeft -lt $CertWarnDays) -or
    $_.SelfSigned -eq $true -or
    $_.Source -eq 'TCP/443 probe (failed)' -or
    $_.Source -eq 'skipped'
} | Sort-Object DaysLeft

$TableFormat = @{
    DaysLeft   = { param($v,$row) if ($v -is [int] -and [int]$v -lt 30) { 'bad' } elseif ($v -is [int] -and [int]$v -lt 60) { 'warn' } else { '' } }
    SelfSigned = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
    Valid      = { param($v,$row) if ($v -eq $true) { 'ok' } elseif ($v -eq $false) { 'bad' } else { '' } }
    Source     = { param($v,$row) if ($v -match 'failed|skipped') { 'warn' } else { '' } }
}
