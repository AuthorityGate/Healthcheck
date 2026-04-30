#Requires -Version 5.1
<#
    HorizonSoap.psm1
    Thin wrapper around VMware.Hv.Helper (Omnissa PowerCLI Horizon snap-in)
    that the SOAP/Web Services API. Used as a fallback data source when the
    REST surface returns stub data on Horizon 8.6 (id+jwt-only on
    /v1/monitor/connection-servers, 404s on /v1/entitlements, etc.).

    Why a wrapper:
      - VMware.Hv.Helper is optional; REST-only deployments still work.
        The wrapper centralizes "is the snap-in available?" + connect/auth
        so plugins don't each repeat the import-or-skip dance.
      - Connect-HVServer (the snap-in's connect cmdlet) is sticky - it sets
        $Global:DefaultHVServers and any later cmdlet implicitly fans out.
        We track the connected sessions so multi-pod runs don't trample
        each other.
#>

# Per-server snap-in session state (mirror of the REST $Script:HVSessions
# hashtable). Key = Server FQDN.
$Script:HVSoapSessions = @{}

function Test-HVSoapAvailable {
    # Returns $true when VMware.Hv.Helper can be imported. Doesn't throw -
    # plugins read this as a gate before attempting SOAP calls.
    try {
        $mod = Get-Module -ListAvailable -Name VMware.Hv.Helper -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending | Select-Object -First 1
        return [bool]$mod
    } catch {
        return $false
    }
}

function Connect-HVSoap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][pscredential]$Credential,
        [string]$Domain,
        [switch]$SkipCertificateCheck
    )
    if (-not (Test-HVSoapAvailable)) {
        throw "VMware.Hv.Helper module not installed. Run Install-Prerequisites.cmd to install via PSGallery."
    }
    Import-Module VMware.Hv.Helper -ErrorAction Stop

    if ($SkipCertificateCheck) {
        # PowerCLI shares cert-validation policy with the rest of the suite.
        # 'Ignore' is intentional for lab/customer environments where the
        # broker uses a self-signed cert; operators tick 'Skip cert validation'
        # explicitly and we honor that.
        try {
            Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session -ErrorAction SilentlyContinue | Out-Null
        } catch { }
    }

    # Connect-HVServer accepts user@domain; if a separate $Domain was passed,
    # promote it into the username when the user didn't already supply one.
    $userName = $Credential.UserName
    if ($Domain -and ($userName -notmatch '@' -and $userName -notmatch '\\')) {
        $userName = "$userName@$Domain"
    }
    $cred = New-Object System.Management.Automation.PSCredential(
        $userName, $Credential.Password)

    # Connect-HVServer doesn't return a session object directly; it sets
    # $Global:DefaultHVServers. We capture the resulting connection so we
    # can disconnect later.
    Connect-HVServer -Server $Server -Credential $cred -ErrorAction Stop | Out-Null

    $sess = $null
    try {
        $sess = $Global:DefaultHVServers | Where-Object { $_.Name -eq $Server -or $_.Name -ieq $Server } | Select-Object -First 1
        if (-not $sess) { $sess = $Global:DefaultHVServers | Select-Object -First 1 }
    } catch { }

    $Script:HVSoapSessions[$Server] = $sess
    return $sess
}

function Disconnect-HVSoap {
    param([string]$Server)
    if ($Server -and $Script:HVSoapSessions.ContainsKey($Server)) {
        try { Disconnect-HVServer -Server $Server -Confirm:$false -Force -ErrorAction SilentlyContinue | Out-Null } catch { }
        $Script:HVSoapSessions.Remove($Server)
    } elseif (-not $Server) {
        try { Disconnect-HVServer -Server * -Confirm:$false -Force -ErrorAction SilentlyContinue | Out-Null } catch { }
        $Script:HVSoapSessions.Clear()
    }
}

function Get-HVSoapSession {
    param([string]$Server)
    if ($Server) { return $Script:HVSoapSessions[$Server] }
    return $Script:HVSoapSessions
}

# Fetch the Connection-Server inventory via SOAP. Returns objects with the
# canonical names plugins read ($c.name, .version, .build, .status,
# .replication) so the existing CS plugins consume SOAP and REST output
# interchangeably.
function Get-HVSoapConnectionServer {
    param([string]$Server)
    if (-not (Test-HVSoapAvailable)) { return @() }
    if ($Server -and -not $Script:HVSoapSessions.ContainsKey($Server)) { return @() }

    # Get-HVConfig -Type ConnectionServer is the SOAP equivalent of REST
    # /v1/config/connection-servers. Returns full per-CS metadata even on
    # builds where REST returns id+jwt-only.
    try {
        $cs = @(Get-HVConfig -Type ConnectionServer -ErrorAction Stop)
        foreach ($c in $cs) {
            if (-not $c) { continue }
            $name    = $null
            $version = $null
            $build   = $null
            $status  = $null
            $repl    = $null
            try { $name = $c.general.name } catch { }
            if (-not $name) { try { $name = $c.dnsName } catch { } }
            try { $version = $c.general.version } catch { }
            try { $build = $c.general.buildNumber } catch { }
            try { $status = $c.status.connectionServerStatus } catch { }
            try { $repl = $c.status.replicationStatus } catch { }
            [pscustomobject]@{
                id          = if ($c.id) { "$($c.id.id)" } else { '' }
                name        = $name
                version     = $version
                build       = $build
                status      = $status
                replication = $repl
                _source     = 'soap'
                _raw        = $c
            }
        }
    } catch { }
}

# Fetch per-pool entitlements via SOAP. Wave 3b ADAM LDAPS reader is the
# preferred authoritative source, but the snap-in is a viable middle path
# when ADAM creds aren't supplied. Returns @{ PoolName; PoolId; Entitlee }
# rows (one per user/group entitlement).
function Get-HVSoapPoolEntitlement {
    param([string]$PoolId)
    if (-not (Test-HVSoapAvailable)) { return @() }
    try {
        $pools = if ($PoolId) {
            @(Get-HVPool -PoolName * -ErrorAction SilentlyContinue | Where-Object { "$($_.Id.Id)" -eq $PoolId })
        } else {
            @(Get-HVPool -ErrorAction SilentlyContinue)
        }
        foreach ($pool in $pools) {
            if (-not $pool) { continue }
            $pname = $null
            try { $pname = $pool.Base.Name } catch { }
            $pid   = $null
            try { $pid = "$($pool.Id.Id)" } catch { }
            try {
                $ent = @(Get-HVEntitlement -ResourceId $pool.Id -ResourceType Desktop -ErrorAction SilentlyContinue)
                foreach ($e in $ent) {
                    $isGroup = $false
                    try { $isGroup = [bool]$e.Base.Group } catch { }
                    [pscustomobject]@{
                        PoolName = $pname
                        PoolId   = $pid
                        Entitlee = $e.Base.LoginName
                        Type     = if ($isGroup) { 'Group' } else { 'User' }
                        _source  = 'soap'
                    }
                }
            } catch { }
        }
    } catch { }
}

Export-ModuleMember -Function `
    Test-HVSoapAvailable, Connect-HVSoap, Disconnect-HVSoap, `
    Get-HVSoapSession, Get-HVSoapConnectionServer, Get-HVSoapPoolEntitlement
