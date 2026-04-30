# Start of Settings
# Operator hint: $Global:EntraSyncServer = 'aadsync.corp.local'
# End of Settings

$Title          = "Microsoft Entra Connect (AAD Connect) Sync Health"
$Header         = "Hybrid identity sync state"
$Comments       = "Probes the on-prem Entra Connect server (formerly Azure AD Connect) via PSRemoting and reads the ADSync module: scheduler state, last full / delta sync timestamps, last error, password-hash sync state, SSO mode (Federated / PHS / PTA / Cloud-only). Hybrid identity = the foundation under M365 SSO; sync gaps cause group-membership drift that cascades into Horizon SAML federation."
$Display        = "List"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "C1 Identity Federation"
$Severity       = "P1"
$Recommendation = "Sync gap > 4h indicates the scheduler is stalled or service-account password expired. Recurring 'export error' = a single object schema problem (re-run with verbose for details). PHS off + PTA off + no AD FS = no SSO method - users will get prompted on every M365 login."

if (-not $Global:EntraSyncServer) {
    [pscustomobject]@{ Note = 'No Entra Connect server set. Define $Global:EntraSyncServer (the AAD Sync server FQDN) in runner.' }
    return
}
$cred = $Global:EntraSyncCredential
if (-not $cred) { $cred = $Global:HVImageScanCredential }
if (-not $cred) {
    [pscustomobject]@{ Server=$Global:EntraSyncServer; Note='No credential available. Set Deep-Scan Creds OR define $Global:EntraSyncCredential.' }
    return
}

$probeBlock = {
    $out = [ordered]@{
        AdSyncModule    = ''
        SyncEnabled     = ''
        SchedulerEnabled = ''
        SyncCycleEnabled = ''
        StagingMode     = ''
        LastSync        = ''
        LastSyncError   = ''
        SignInMethod    = ''
        AdConnectorVersion = ''
        Note            = ''
    }
    try {
        Import-Module ADSync -ErrorAction Stop
        $out.AdSyncModule = 'OK'
        $sched = Get-ADSyncScheduler -ErrorAction SilentlyContinue
        if ($sched) {
            $out.SyncEnabled       = [string]$sched.SyncCycleEnabled
            $out.SchedulerEnabled  = [string]$sched.SchedulerSuspended -eq 'False'
            $out.StagingMode       = [string]$sched.StagingModeEnabled
            $out.LastSync          = if ($sched.NextSyncCyclePolicyType) { 'See NextSync below' } else { '' }
        }
        $runs = Get-ADSyncConnectorRunStatus -ErrorAction SilentlyContinue | Sort-Object StartDate -Descending | Select-Object -First 5
        if ($runs) {
            $latest = $runs[0]
            $out.LastSync = $latest.StartDate.ToString('yyyy-MM-dd HH:mm')
            if ($latest.Result -ne 'success') { $out.LastSyncError = "$($latest.RunStepResults | Out-String)".Substring(0,200) }
        }
    } catch {
        $out.Note = 'ADSync PowerShell module not available on this machine. Confirm it really is the Entra Connect host.'
    }
    [pscustomobject]$out
}

try {
    $session = New-PSSession -ComputerName $Global:EntraSyncServer -Credential $cred -ErrorAction Stop
    $r = Invoke-Command -Session $session -ScriptBlock $probeBlock
    Remove-PSSession $session -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Server         = $Global:EntraSyncServer
        ModuleStatus   = $r.AdSyncModule
        SyncEnabled    = $r.SyncEnabled
        SchedulerEnabled = $r.SchedulerEnabled
        StagingMode    = $r.StagingMode
        LastSync       = $r.LastSync
        LastSyncError  = $r.LastSyncError
        Note           = $r.Note
    }
} catch {
    [pscustomobject]@{ Server=$Global:EntraSyncServer; ModuleStatus='unreachable'; Note="WinRM probe failed: $($_.Exception.Message)" }
}

$TableFormat = @{
    SyncEnabled = { param($v,$row) if ($v -eq 'True') { 'ok' } elseif ($v -eq 'False') { 'bad' } else { '' } }
    StagingMode = { param($v,$row) if ($v -eq 'True') { 'warn' } else { '' } }
}
