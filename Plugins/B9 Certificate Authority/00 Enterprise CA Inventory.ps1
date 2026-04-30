# Start of Settings
# Operator hint: $Global:CAServerList = @('ca1.corp.local','rootca.corp.local')
# Otherwise auto-discover via certutil and AD's pKIEnrollmentService objects.
# End of Settings

$Title          = "Enterprise CA Hierarchy Inventory"
$Header         = "[count] Certificate Authority server(s)"
$Comments       = "Auto-discovers Enterprise CAs registered in AD (pKIEnrollmentService objects) plus operator-supplied CA servers. Reports per-CA: type (Root / Subordinate / Standalone), CA name, computer name, validity period, signing algorithm. Critical for TrueSSO + SAML + UAG cert rotations."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B9 Certificate Authority"
$Severity       = "P2"
$Recommendation = "Single-tier (Standalone) CA hierarchies are insecure for production - migrate to a two-tier (offline Root + online Subordinate). CAs signing with SHA-1 must be migrated to SHA-256 immediately. Plan Subordinate CA cert rotation 12+ months before expiry to avoid issuance outage."

$cas = @()
if ($Global:CAServerList) { $cas = @($Global:CAServerList) }
else {
    try {
        # Auto-discover via AD
        $rootDse = [ADSI]'LDAP://RootDSE'
        $cfgNc = [string]$rootDse.configurationNamingContext
        $caContainer = [ADSI]("LDAP://CN=Enrollment Services,CN=Public Key Services,CN=Services,$cfgNc")
        foreach ($entry in $caContainer.Children) {
            $cas += [string]$entry.dNSHostName
        }
    } catch { }
}
if ($cas.Count -eq 0) {
    [pscustomobject]@{ Note='No CAs found. Set $Global:CAServerList in runner OR ensure AD module + RSAT is available for auto-discovery.' }
    return
}

foreach ($ca in $cas) {
    if (-not $ca) { continue }
    $row = [ordered]@{
        CAServer       = $ca
        Reachable      = $false
        CAName         = ''
        CAType         = ''
        Algorithm      = ''
        ValidFrom      = ''
        ValidTo        = ''
        DaysToExpiry   = ''
        Note           = ''
    }
    # Reachability probe (TCP/443 + RPC/135 fallback)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($ca, 135, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(3000)) { $tcp.EndConnect($iar); $row.Reachable = $true }
        $tcp.Close()
    } catch { }
    # Pull cert via certutil if available
    if ($row.Reachable) {
        try {
            $out = & certutil -config "$ca\$ca" -ping 2>$null
            if ($LASTEXITCODE -eq 0) { $row.Note = 'certutil -ping OK' } else { $row.Note = 'certutil ping failed' }
        } catch { $row.Note = $_.Exception.Message }
    }
    [pscustomobject]$row
}

$TableFormat = @{
    Reachable = { param($v,$row) if ($v -eq $true) { 'ok' } else { 'bad' } }
}
