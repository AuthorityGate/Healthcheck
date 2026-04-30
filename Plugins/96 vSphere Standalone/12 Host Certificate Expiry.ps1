# Start of Settings
# Days-to-expiry threshold.
$WarnDays = 60
# End of Settings

$Title          = "ESXi Host Certificate Expiry"
$Header         = "Per-host machine SSL certificate (every host listed)"
$Comments       = "VMware KB 2113034 / vSphere Security Guide: ESXi machine SSL certs default to 2 years, signed by VMCA. When they expire (or are about to), management agents (hostd, vpxa) lose trust with vCenter - host shows 'Disconnected' until renewed. Lists every host's certificate so the audit is verifiable; rows under threshold flagged."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P1"
$Recommendation = "Host -> Configure -> Certificate -> 'Renew'. For VMCA-signed: re-issue from vCenter. For external CA: replace via 'certificate-manager' on the host or PowerCLI 'New-VMHostCertificate'."

if (-not $Global:VCConnected) { return }

$hosts = @(Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Note='Get-VMHost returned no hosts.' }
    return
}

foreach ($h in $hosts) {
    $row = [pscustomobject]@{
        Host       = $h.Name
        Cluster    = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
        Subject    = ''
        Issuer     = ''
        NotAfter   = ''
        DaysLeft   = ''
        Thumbprint = ''
        Status     = ''
    }
    if ($h.ConnectionState -ne 'Connected') {
        $row.Status = 'SKIPPED (host disconnected)'
        $row
        continue
    }
    try {
        $cert = $h.ExtensionData.Config.Certificate
        if (-not $cert) {
            $row.Status = 'NO CERT RETURNED'
            $row
            continue
        }
        $x = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(,([byte[]]$cert))
        $days = [int]($x.NotAfter - (Get-Date)).TotalDays
        $row.Subject    = "$($x.Subject)"
        $row.Issuer     = "$($x.Issuer)"
        $row.NotAfter   = $x.NotAfter.ToString('yyyy-MM-dd')
        $row.DaysLeft   = $days
        $row.Thumbprint = "$($x.Thumbprint)"
        $row.Status = if ($days -lt 0) { 'EXPIRED' }
                      elseif ($days -lt 30) { "EXPIRING ($days d)" }
                      elseif ($days -lt $WarnDays) { "WARN ($days d)" }
                      else { "OK ($days d)" }
        $row
    } catch {
        $row.Status = "ERR: $($_.Exception.Message.Substring(0, [Math]::Min(80, $_.Exception.Message.Length)))"
        $row
    }
}

$TableFormat = @{
    DaysLeft = { param($v,$row) if ("$v" -match '^-?\d+$' -and [int]"$v" -lt 30) { 'bad' } elseif ("$v" -match '^\d+$' -and [int]"$v" -lt 60) { 'warn' } else { '' } }
    Status   = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'EXPIR|ERR|NO CERT') { 'bad' } elseif ("$v" -match 'WARN|SKIP') { 'warn' } else { '' } }
}
