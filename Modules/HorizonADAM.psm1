#Requires -Version 5.1
<#
    HorizonADAM.psm1
    Read-only LDAPS / LDAP pull from each Connection Server's local AD-LDS
    (ADAM) instance. The ADAM directory is the authoritative source for
    Horizon pool entitlements - REST 404s on most entitlement endpoints on
    Horizon 8.6 even when /v1/entitlements is documented to exist.

    Connection model:
      - Port 636 (LDAPS) preferred, fallback to 389 (LDAP) when LDAPS handshake
        fails (some labs leave LDAPS un-configured on the broker).
      - DN base 'OU=Applications,DC=vdi,DC=vmware,DC=int' is the canonical
        Horizon ADAM root.
      - Service account is OPERATOR-CONFIGURABLE - never hardcoded. Plugins
        read the credential from the credential profile picker via the
        $Global:ADAMCredential variable the GUI sets.

    Read-only contract: this module does NOT call Add/Modify/Remove anywhere.
    Only Search-style operations. The user explicitly approved this PIVOT on
    condition no writes are performed.
#>

# Connect to ADAM and run a search. Returns System.DirectoryServices.SearchResult
# objects so callers can pick whichever attributes they need without forcing
# a single shape on this module. Throws on connect/auth failure - callers
# wrap in try/catch and emit diagnostic rows.
function Search-HVAdam {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$BaseDN,
        [Parameter(Mandatory)][string]$Filter,
        [pscredential]$Credential,
        [int]$Port = 636,
        [string[]]$Properties = @('*'),
        [switch]$LdapInsteadOfLdaps,
        [int]$TimeoutSec = 30,
        [int]$PageSize = 500
    )
    if ($LdapInsteadOfLdaps -and $Port -eq 636) { $Port = 389 }

    $authType = [System.DirectoryServices.Protocols.AuthType]::Negotiate
    $id = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier($Server, $Port)
    $conn = New-Object System.DirectoryServices.Protocols.LdapConnection($id)
    $conn.AuthType = $authType
    $conn.SessionOptions.ProtocolVersion = 3
    if ($Port -eq 636) {
        $conn.SessionOptions.SecureSocketLayer = $true
        # Lab/customer brokers use self-signed certs; we trust the channel
        # because the ADAM creds are short-lived and read-only. Mirrors the
        # 'Skip cert validation' option already exposed everywhere else.
        $conn.SessionOptions.VerifyServerCertificate = { param($c, $cert) $true }
    }
    $conn.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)

    if ($Credential) {
        $netcred = New-Object System.Net.NetworkCredential(
            $Credential.UserName,
            $Credential.GetNetworkCredential().Password,
            '')
        $conn.Bind($netcred)
    } else {
        $conn.Bind()
    }

    $req = New-Object System.DirectoryServices.Protocols.SearchRequest(
        $BaseDN,
        $Filter,
        [System.DirectoryServices.Protocols.SearchScope]::Subtree,
        $Properties)

    # Page through results so very large estates (10k+ pools / entitlements)
    # don't trip the server-side size limit (default 1000).
    $pageReq = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($PageSize)
    $req.Controls.Add($pageReq) | Out-Null

    $allEntries = New-Object System.Collections.ArrayList
    while ($true) {
        $resp = $conn.SendRequest($req)
        foreach ($e in $resp.Entries) { [void]$allEntries.Add($e) }
        $pageResp = $resp.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] } | Select-Object -First 1
        if (-not $pageResp -or -not $pageResp.Cookie -or $pageResp.Cookie.Length -eq 0) { break }
        $pageReq.Cookie = $pageResp.Cookie
    }
    return $allEntries
}

# Fetch every desktop-pool entitlement in one shot and project into the
# canonical row shape plugins expect. Returns @{ PoolDN; PoolCN; Entitlee }
# rows; exactly one row per user/group entitlement. Use this when REST
# /v1/entitlements + /v2/entitlements both 404.
function Get-HVAdamPoolEntitlement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [pscredential]$Credential,
        [string]$BaseDN = 'OU=Applications,DC=vdi,DC=vmware,DC=int',
        [int]$Port = 636,
        [switch]$LdapInsteadOfLdaps
    )
    # Horizon stores per-pool entitlements as 'pae-DesktopEntitlement' (and
    # 'pae-ApplicationEntitlement' for app pools). Each entry's
    # pae-MemberDN points at the user/group DN. We pull both pool entries
    # and entitlement entries, then join in PowerShell.
    $entitlementFilter = '(|(objectClass=pae-DesktopEntitlement)(objectClass=pae-ApplicationEntitlement))'
    $rows = New-Object System.Collections.ArrayList
    $entries = Search-HVAdam -Server $Server -BaseDN $BaseDN -Filter $entitlementFilter `
        -Credential $Credential -Port $Port -LdapInsteadOfLdaps:$LdapInsteadOfLdaps `
        -Properties @('cn','distinguishedName','pae-DisplayName','pae-MemberDN','pae-Pool','pae-Application','objectClass')
    foreach ($entry in $entries) {
        $cn = if ($entry.Attributes.Contains('cn')) { "$($entry.Attributes['cn'][0])" } else { '' }
        $dn = "$($entry.DistinguishedName)"
        $disp = if ($entry.Attributes.Contains('pae-DisplayName')) { "$($entry.Attributes['pae-DisplayName'][0])" } else { $cn }
        $resourceDn = if ($entry.Attributes.Contains('pae-Pool')) { "$($entry.Attributes['pae-Pool'][0])" }
                      elseif ($entry.Attributes.Contains('pae-Application')) { "$($entry.Attributes['pae-Application'][0])" }
                      else { '' }
        $resourceType = if ($entry.Attributes.Contains('pae-Application')) { 'Application' } else { 'Desktop' }
        $members = @()
        if ($entry.Attributes.Contains('pae-MemberDN')) {
            for ($i=0; $i -lt $entry.Attributes['pae-MemberDN'].Count; $i++) {
                $members += "$($entry.Attributes['pae-MemberDN'][$i])"
            }
        }
        if ($members.Count -eq 0) {
            [void]$rows.Add([pscustomobject]@{
                EntitlementCN  = $cn
                EntitlementDN  = $dn
                DisplayName    = $disp
                ResourceType   = $resourceType
                ResourceDN     = $resourceDn
                MemberDN       = '(none)'
                _source        = 'adam'
            })
        } else {
            foreach ($m in $members) {
                [void]$rows.Add([pscustomobject]@{
                    EntitlementCN  = $cn
                    EntitlementDN  = $dn
                    DisplayName    = $disp
                    ResourceType   = $resourceType
                    ResourceDN     = $resourceDn
                    MemberDN       = $m
                    _source        = 'adam'
                })
            }
        }
    }
    return $rows.ToArray()
}

# Pull every pool object (pae-Pool / pae-Application) so the operator gets
# a definitive pool inventory even when REST /v2/desktop-pools returns
# stub-only data.
function Get-HVAdamPool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [pscredential]$Credential,
        [string]$BaseDN = 'OU=Applications,DC=vdi,DC=vmware,DC=int',
        [int]$Port = 636,
        [switch]$LdapInsteadOfLdaps
    )
    $filter = '(|(objectClass=pae-Pool)(objectClass=pae-Application))'
    $entries = Search-HVAdam -Server $Server -BaseDN $BaseDN -Filter $filter `
        -Credential $Credential -Port $Port -LdapInsteadOfLdaps:$LdapInsteadOfLdaps `
        -Properties @('cn','distinguishedName','pae-DisplayName','objectClass','pae-PoolType','pae-VmIdleTimeout','pae-Disabled')
    $rows = New-Object System.Collections.ArrayList
    foreach ($entry in $entries) {
        $cn = if ($entry.Attributes.Contains('cn')) { "$($entry.Attributes['cn'][0])" } else { '' }
        $disp = if ($entry.Attributes.Contains('pae-DisplayName')) { "$($entry.Attributes['pae-DisplayName'][0])" } else { $cn }
        $isApp = $false
        if ($entry.Attributes.Contains('objectClass')) {
            for ($i=0; $i -lt $entry.Attributes['objectClass'].Count; $i++) {
                if ("$($entry.Attributes['objectClass'][$i])" -eq 'pae-Application') { $isApp = $true; break }
            }
        }
        $disabled = $false
        if ($entry.Attributes.Contains('pae-Disabled')) {
            $disabled = ("$($entry.Attributes['pae-Disabled'][0])" -ieq 'TRUE' -or "$($entry.Attributes['pae-Disabled'][0])" -eq '1')
        }
        [void]$rows.Add([pscustomobject]@{
            CN          = $cn
            DN          = "$($entry.DistinguishedName)"
            DisplayName = $disp
            Type        = if ($isApp) { 'Application' } else { 'Desktop' }
            Disabled    = $disabled
            _source     = 'adam'
        })
    }
    return $rows.ToArray()
}

# Test connectivity + bind without pulling data. The plugin runner uses
# this to short-circuit cleanly when ADAM credentials weren't supplied.
function Test-HVAdamConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [pscredential]$Credential,
        [int]$Port = 636,
        [switch]$LdapInsteadOfLdaps
    )
    try {
        $null = Search-HVAdam -Server $Server -BaseDN 'CN=Schema,CN=Configuration,DC=vdi,DC=vmware,DC=int' `
            -Filter '(objectClass=top)' -Properties @('objectClass') `
            -Credential $Credential -Port $Port -LdapInsteadOfLdaps:$LdapInsteadOfLdaps -PageSize 1
        return [pscustomobject]@{ Connected=$true; Error=$null }
    } catch {
        return [pscustomobject]@{ Connected=$false; Error=$_.Exception.Message }
    }
}

Export-ModuleMember -Function `
    Search-HVAdam, Get-HVAdamPoolEntitlement, Get-HVAdamPool, Test-HVAdamConnection
