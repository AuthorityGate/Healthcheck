# Start of Settings
# End of Settings

$Title          = "DEM Logon / Triggered Tasks Inventory"
$Header         = "[count] logon + triggered task definition(s)"
$Comments       = "Every Logon Task and Triggered Task XML on the DEM share. These run during user logon - excessive count or expensive tasks are a leading cause of slow VDI logon times. Includes task type, command, condition, run-as, and trigger event."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "92 Dynamic Environment Manager"
$Severity       = "P3"
$Recommendation = "More than ~20 logon tasks per persona warrants review - excessive logon-time work is a leading cause of slow VDI logon. Audit for tasks that should be triggered (not always-on at logon). Run-as=System combined with a network operation is fragile (DC unreachable at logon time = stuck task)."

if (-not $Global:DEMConfigShare -or -not (Test-Path $Global:DEMConfigShare)) {
    [pscustomobject]@{ Note='DEMConfigShare not set or unreachable.' }
    return
}

$rows = @()
foreach ($folder in @('LogonTasks','Triggered Tasks')) {
    $base = Join-Path $Global:DEMConfigShare $folder
    if (-not (Test-Path $base)) { continue }
    foreach ($x in (Get-ChildItem -Path $base -Recurse -Filter *.xml -ErrorAction SilentlyContinue)) {
        $name=''; $cmd=''; $cond=''; $type=''; $runas=''; $trigger=''
        try {
            [xml]$xml = Get-Content -LiteralPath $x.FullName -ErrorAction Stop
            $name = $xml.SelectSingleNode('//displayname').InnerText
            $cmd  = ($xml.SelectSingleNode('//command')).InnerText
            $cond = ($xml.SelectSingleNode('//condition')).InnerText
            $type = ($xml.SelectSingleNode('//tasktype')).InnerText
            $runas = ($xml.SelectSingleNode('//runas')).InnerText
            $trigger = ($xml.SelectSingleNode('//trigger')).InnerText
        } catch { }
        $rows += [pscustomobject]@{
            Folder   = $folder
            Name     = if ($name) { $name } else { $x.BaseName }
            Type     = $type
            Trigger  = $trigger
            RunAs    = $runas
            Command  = if ($cmd) { $cmd.Substring(0,[Math]::Min(120,$cmd.Length)) } else { '' }
            Condition = if ($cond) { $cond.Substring(0,[Math]::Min(60,$cond.Length)) } else { '' }
            File     = $x.Name
        }
    }
}
if ($rows.Count -eq 0) {
    [pscustomobject]@{ Note='No logon / triggered tasks defined.' }
    return
}
$rows | Sort-Object Folder, Name
