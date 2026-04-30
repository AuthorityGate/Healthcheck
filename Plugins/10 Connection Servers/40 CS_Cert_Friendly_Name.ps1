# Start of Settings
# End of Settings

$Title          = 'CS Certificate Friendly-Name Compliance'
$Header         = "CS cert friendly-name vs documented requirement"
$Comments       = "Horizon CS finds its SSL cert by friendly-name 'vdm' (case-sensitive). Wrong name = CS uses self-signed default = browser warnings + client errors."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'P1'
$Recommendation = "Tier 2 in-guest probe (via WinRM) checks each CS for the cert with friendly-name 'vdm'. Without it, the CS cannot present a CA-signed cert. Set friendly-name 'vdm' (case-sensitive) on the renewed cert."

if (-not (Get-HVRestSession)) { return }

$cred = if (Test-Path Variable:Global:HVImageScanCredential) { $Global:HVImageScanCredential } else { $null }

$servers = New-Object System.Collections.Generic.HashSet[string]
try {
    $cs = Invoke-HVRest -Path '/v1/monitor/connection-servers' -NoPaging
    foreach ($c in @($cs)) {
        if ($c.name) { [void]$servers.Add($c.name) }
    }
} catch { }
if ($servers.Count -eq 0) { return }

$probe = {
    $r = @{}
    try {
        $certs = Get-ChildItem Cert:\LocalMachine\My -ErrorAction Stop
        $vdmCert = $certs | Where-Object { $_.FriendlyName -eq 'vdm' }
        if ($vdmCert) {
            $r.HasVdmCert = $true
            $r.Subject = $vdmCert.Subject
            $r.Issuer = $vdmCert.Issuer
            $r.NotAfter = $vdmCert.NotAfter
            $r.DaysToExpiry = [int]($vdmCert.NotAfter - (Get-Date)).TotalDays
            $r.HasSAN = ($vdmCert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' }).Count -gt 0
        } else {
            $r.HasVdmCert = $false
            $r.AnyCerts = @($certs | Select-Object -Property FriendlyName, Subject -First 5)
        }
    } catch {
        $r.Error = $_.Exception.Message
    }
    return $r
}

foreach ($srv in $servers) {
    if (-not $cred) {
        [pscustomobject]@{
            ConnectionServer = $srv; HasVdmCert = '(unknown - need creds)'; Issuer = ''; DaysToExpiry = ''
            Note = 'Set $Global:HVImageScanCredential for cert probe.'
        }
        continue
    }
    try {
        $session = New-PSSession -ComputerName $srv -Credential $cred -ErrorAction Stop
        $g = Invoke-Command -Session $session -ScriptBlock $probe
        Remove-PSSession $session -ErrorAction SilentlyContinue
        [pscustomobject]@{
            ConnectionServer = $srv
            HasVdmCert       = $g.HasVdmCert
            Issuer           = $g.Issuer
            Subject          = $g.Subject
            HasSAN           = $g.HasSAN
            DaysToExpiry     = $g.DaysToExpiry
            Note             = if (-not $g.HasVdmCert) { "MISSING vdm-named cert; CS will use self-signed" } elseif ($g.DaysToExpiry -lt 60) { "Cert expires in $($g.DaysToExpiry) days" } else { '' }
        }
    } catch {
        [pscustomobject]@{
            ConnectionServer = $srv; HasVdmCert = '(probe failed)'; Note = $_.Exception.Message
        }
    }
}

$TableFormat = @{
    HasVdmCert = { param($v,$row) if ($v -eq $false) { 'bad' } else { '' } }
    Note = { param($v,$row) if ($v -match 'MISSING|expires in') { 'bad' } else { '' } }
}
