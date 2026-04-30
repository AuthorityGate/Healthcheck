# Start of Settings
# End of Settings

$Title          = 'Per-Category Probe Diagnosis'
$Header         = 'For every plugin category: which backend feeds it, which API was reached, what is blocking deeper data'
$Comments       = @"
One row per plugin category. Tells the operator at-a-glance:
- What backend(s) the category's plugins read (Horizon REST / SOAP / ADAM, vCenter, AppVol, etc.)
- Whether that backend is connected this run
- Whether the dominant REST endpoint for the category returned rich data, stub data, 0 items, or 404s
- What the next step is when something is missing (install Hv.Helper, set ADAM cred, supply WinRM creds, etc.)

This row is your trust signal: when a category emits sparse data, you can see immediately whether the cause is the operator (didn't tick the target / didn't supply creds), the API (REST stub on Horizon 8.6), or the network (WinRM 5985 blocked).
"@
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '00 Initialize'
$Severity       = 'Info'
$Recommendation = 'When DataPath = stub, the underlying REST endpoint returned only id+jwt-style fields - the v0.94.0 multi-source pivot kicks in (SOAP via VMware.Hv.Helper + ADAM LDAPS + WinRM). Install missing prerequisites flagged in NextStep to lift the data ceiling for that category.'

$connected = @($Global:HVConnectedBackends)
if (-not $connected -or $connected.Count -eq 0) {
    # Re-derive from session presence - script-scope $connected may be empty
    # when this plugin runs from a console rather than the GUI runspace.
    $connected = @()
    if (Get-HVRestSession) { $connected += 'Horizon' }
    try { if ($Global:DefaultVIServer -or $Global:DefaultVIServers) { $connected += 'vCenter' } } catch { }
    if ($Global:ADServerFqdn) { $connected += 'AD' }
}

$endpointMap = $null
if ((Get-HVRestSession) -and (Get-Command Get-HVEndpointMap -ErrorAction SilentlyContinue)) {
    try { $endpointMap = Get-HVEndpointMap } catch { }
}

# Probe state for the connected pod. Used to flag stub-mode CS data, missing
# Hv.Helper, missing ADAM cred, etc.
$cssStub = $false
if ((Get-HVRestSession) -and (Get-Command Test-HVCSDataIsStub -ErrorAction SilentlyContinue)) {
    try { $cssStub = Test-HVCSDataIsStub } catch { }
}
$haveHvHelper = [bool](Get-Module -ListAvailable VMware.Hv.Helper -ErrorAction SilentlyContinue)
$haveAdamCred = [bool]$Global:HVAdamCredential
$haveWinRMCred = [bool]$Global:HVImageScanCredential

# Helper: does the endpoint map say a path is healthy?
function _EndpointStatus($name) {
    if (-not $endpointMap -or -not $endpointMap.Contains($name)) { return $null }
    return $endpointMap[$name].Status
}

# Build one row per category. Each row explains the category in plain
# language - what does this category cover, what does it need, where does
# the data come from, what's the verdict.
$catalog = @(
    @{ Cat='00 Initialize';                Backend='Internal'; Endpoints=@();                                     Cover='Session bootstrap, schema dump, endpoint discovery, config echo' }
    @{ Cat='10 Connection Servers';        Backend='Horizon';  Endpoints=@('connection-servers-monitor','connection-servers-config'); Cover='CS inventory, version drift, certificate, replication, time-skew, SAML/RADIUS auth providers' }
    @{ Cat='20 Cloud Pod Architecture';    Backend='Horizon';  Endpoints=@('pods','sites');                       Cover='Federation members, global entitlements, CPA pairing' }
    @{ Cat='30 Desktop Pools';             Backend='Horizon';  Endpoints=@('desktop-pools','entitlements');       Cover='Pool inventory, capacity, entitlements (REST + ADAM fallback), provisioning errors, customization specs' }
    @{ Cat='40 RDS Farms';                 Backend='Horizon';  Endpoints=@('farms');                              Cover='RDS farm inventory, server load balancing, application pools, session limits' }
    @{ Cat='50 Machines';                  Backend='Horizon';  Endpoints=@('machines');                           Cover='Per-machine state, agent version, problem/orphaned/missing machines' }
    @{ Cat='60 Sessions';                  Backend='Horizon';  Endpoints=@('sessions');                           Cover='Active + disconnected sessions, by user/pool/protocol' }
    @{ Cat='70 Events';                    Backend='Horizon';  Endpoints=@('audit-events');                       Cover='Audit events, failed authentications, errors, provisioning failures (last 7-30 days)' }
    @{ Cat='80 Licensing and Certificates'; Backend='Horizon'; Endpoints=@();                                     Cover='Horizon license usage, gateway certs, CS certs, smart-card CA trust, CRL state' }
    @{ Cat='90 Gateways';                  Backend='Horizon';  Endpoints=@('gateways');                           Cover='Connection Server gateways + UAG inventory + health' }
    @{ Cat='91 App Volumes';               Backend='AppVolumes'; Endpoints=@();                                   Cover='AppStacks, Writable Volumes, attachments, agent versions' }
    @{ Cat='92 Dynamic Environment Manager'; Backend='Internal'; Endpoints=@();                                   Cover='DEM config share + archive share + agent probe (filesystem-based, no REST)' }
    @{ Cat='93 Enrollment Server';         Backend='Horizon';  Endpoints=@('enrollment-servers');                 Cover='True SSO Enrollment Servers (only when configured)' }
    @{ Cat='94 NSX';                       Backend='NSX';      Endpoints=@();                                     Cover='NSX-T edges, segments, distributed firewall' }
    @{ Cat='95 vSphere Backing Infra';     Backend='vCenter';  Endpoints=@();                                     Cover='Cluster + DRS + HA + DPM + admission control + EVC' }
    @{ Cat='96 vSphere Standalone';        Backend='vCenter';  Endpoints=@();                                     Cover='ESXi host hardware, network, storage, alarms, events' }
    @{ Cat='97 vSphere for Horizon';       Backend='vCenter';  Endpoints=@();                                     Cover='Horizon-relevant vCenter inventory: clusters/networks/datastores carrying Horizon pools' }
    @{ Cat='97 Nutanix Prism';             Backend='Nutanix';  Endpoints=@();                                     Cover='AHV/Prism cluster, host, VM, container, alerts (when Nutanix is selected)' }
    @{ Cat='98 vSAN';                      Backend='vCenter';  Endpoints=@();                                     Cover='vSAN slack space, fault domains, deduplication, health checks' }
    @{ Cat='99 vSphere Lifecycle';         Backend='vCenter';  Endpoints=@();                                     Cover='vLCM cluster image baselines, last remediation, vendor add-on parity' }
    @{ Cat='A0 Hardware';                  Backend='vCenter';  Endpoints=@();                                     Cover='Per-host BIOS/firmware/SMART, NIC firmware, HBA queue depth' }
    @{ Cat='B0 Imprivata';                 Backend='Horizon';  Endpoints=@();                                     Cover='Imprivata OneSign / SSO + tap-and-go integration (only when configured)' }
    @{ Cat='B1 Identity Manager';          Backend='Horizon';  Endpoints=@();                                     Cover='Workspace ONE Access integration on the broker (only when configured)' }
    @{ Cat='B2 Multi-Factor Auth';         Backend='Horizon';  Endpoints=@();                                     Cover='RADIUS / SAML / smart-card MFA stack' }
    @{ Cat='B3 Active Directory';          Backend='AD';       Endpoints=@();                                     Cover='Forest/domain levels, KRBTGT, password policy, LAPS, replication, DCs (RSAT-driven)' }
    @{ Cat='B4 DNS DHCP';                  Backend='AD';       Endpoints=@();                                     Cover='DNS scavenging, DHCP scope coverage, reservations, zone health (RSAT-driven)' }
    @{ Cat='B5 Workspace ONE Access';      Backend='vIDM';     Endpoints=@();                                     Cover='Tenants, identity providers, audit, federation' }
    @{ Cat='B6 Workspace ONE UEM';         Backend='WS1UEM';   Endpoints=@();                                     Cover='Devices, smart groups, app catalog, compliance' }
    @{ Cat='B7 Backup and DR';             Backend='vCenter';  Endpoints=@();                                     Cover='Veeam / Avamar / NetBackup job state, RPO compliance' }
    @{ Cat='B8 FSLogix';                   Backend='AD';       Endpoints=@();                                     Cover='Profile container size, mount latency, AD/SMB integration' }
    @{ Cat='B9 Certificate Authority';     Backend='AD';       Endpoints=@();                                     Cover='Issuing CA health, CRL freshness, template inventory' }
    @{ Cat='C0 SQL Server Health';         Backend='AD';       Endpoints=@();                                     Cover='Event DB SQL host: TempDB, AlwaysOn, backup chain' }
    @{ Cat='C1 Identity Federation';       Backend='AD';       Endpoints=@();                                     Cover='ADFS / Entra Connect health' }
    @{ Cat='C2 Hardening Guide';           Backend='Multi';    Endpoints=@();                                     Cover='CIS Benchmark + DISA STIG cross-reference for the connected stack' }
    @{ Cat='C3 License Lifecycle';         Backend='Multi';    Endpoints=@();                                     Cover='License calendar across Horizon, vCenter, App Volumes, Workspace ONE' }
)

foreach ($entry in $catalog) {
    $backend = $entry.Backend
    $isConnected = $false
    if ($backend -eq 'Internal') {
        $isConnected = $true
    } elseif ($backend -eq 'Multi') {
        $isConnected = ($connected.Count -gt 0)
    } elseif ($backend -eq 'AD') {
        $isConnected = [bool]$Global:ADServerFqdn -or ($connected -contains 'AD')
    } else {
        $isConnected = ($connected -contains $backend)
    }

    $dataPath = ''
    $nextStep = ''
    if (-not $isConnected) {
        $dataPath = 'not connected'
        $nextStep = "Tick '$backend' on the starter dialog and supply credentials on its tab."
    } elseif ($entry.Endpoints.Count -gt 0) {
        $statuses = foreach ($ep in $entry.Endpoints) { _EndpointStatus $ep }
        $statuses = @($statuses | Where-Object { $_ })
        if ($statuses.Count -eq 0) {
            $dataPath = 'unprobed'
        } elseif (($statuses | Where-Object { $_ -eq 'ok' }).Count -eq $statuses.Count) {
            $dataPath = 'ok'
        } elseif (($statuses | Where-Object { $_ -eq 'stub' }).Count -gt 0) {
            $dataPath = 'stub'
            $bits = @()
            if (-not $haveHvHelper) { $bits += 'install VMware.Hv.Helper (Horizon tab badge -> Install-Prerequisites.cmd)' }
            if (-not $haveAdamCred) { $bits += "set 'ADAM credential...' on the Horizon tab (read-only LDAPS pull becomes authoritative for entitlements)" }
            if (-not $haveWinRMCred) { $bits += "set 'Deep-Scan Creds' on the main form (WinRM fallback fills in CS hardware + version)" }
            if ($bits.Count -gt 0) { $nextStep = ($bits -join '; ') } else { $nextStep = 'multi-source fallbacks engaged.' }
        } elseif (($statuses | Where-Object { $_ -match '^4\d{2}$' -or $_ -match '^5\d{2}$' }).Count -gt 0) {
            $dataPath = 'http-error'
            $nextStep = 'Endpoint returned 4xx/5xx - Connection Server logs typically explain why (check vmware-vdmsg + vmware-cs-monitor logs).'
        } elseif (($statuses | Where-Object { $_ -eq 'empty' }).Count -gt 0) {
            $dataPath = 'empty'
            $nextStep = "Endpoint reachable but 0 items - likely no $backend objects of this type are configured on this pod."
        } else {
            $dataPath = ($statuses -join ',')
        }
    } else {
        $dataPath = 'connected'
    }

    [pscustomobject]@{
        Category = $entry.Cat
        Backend  = $backend
        Connected = $isConnected
        Coverage = $entry.Cover
        DataPath = $dataPath
        NextStep = $nextStep
    }
}

$TableFormat = @{
    Connected = { param($v,$row) if ($v -eq $true) { 'ok' } else { 'warn' } }
    DataPath  = { param($v,$row)
        if ($v -eq 'ok' -or $v -eq 'connected') { 'ok' }
        elseif ($v -eq 'not connected') { 'warn' }
        elseif ($v -eq 'stub' -or $v -eq 'empty') { 'warn' }
        elseif ($v -match '^4|^5') { 'bad' }
        else { '' }
    }
}
