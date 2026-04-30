# Start of Settings
# Required vCenter privileges for the Horizon service account, per
# 'Horizon Console Administration Guide -> Privileges Required for the
# vCenter Server User' / KB 88016.
$RequiredPrivileges = @(
    'Folder.Create','Folder.Delete',
    'Datacenter.Create','Datacenter.Delete',
    'Datastore.AllocateSpace','Datastore.Browse','Datastore.DeleteFile','Datastore.FileManagement','Datastore.UpdateVirtualMachineFiles','Datastore.UpdateVirtualMachineMetadata',
    'Network.Assign',
    'Resource.AssignVMToPool','Resource.HotMigrate','Resource.ColdMigrate',
    'VirtualMachine.Inventory.CreateFromExisting','VirtualMachine.Inventory.Create','VirtualMachine.Inventory.Register','VirtualMachine.Inventory.Delete','VirtualMachine.Inventory.Move',
    'VirtualMachine.Provisioning.Customize','VirtualMachine.Provisioning.Clone','VirtualMachine.Provisioning.DeployTemplate','VirtualMachine.Provisioning.MarkAsTemplate','VirtualMachine.Provisioning.MarkAsVM','VirtualMachine.Provisioning.ReadCustSpecs','VirtualMachine.Provisioning.ModifyCustSpecs',
    'VirtualMachine.Config.AddExistingDisk','VirtualMachine.Config.AddNewDisk','VirtualMachine.Config.AddRemoveDevice','VirtualMachine.Config.AdvancedConfig','VirtualMachine.Config.Annotation','VirtualMachine.Config.CPUCount','VirtualMachine.Config.DiskExtend','VirtualMachine.Config.EditDevice','VirtualMachine.Config.Memory','VirtualMachine.Config.RawDevice','VirtualMachine.Config.RemoveDisk','VirtualMachine.Config.Rename','VirtualMachine.Config.ResetGuestInfo','VirtualMachine.Config.Resource','VirtualMachine.Config.Settings','VirtualMachine.Config.UpgradeVirtualHardware',
    'VirtualMachine.Interact.PowerOff','VirtualMachine.Interact.PowerOn','VirtualMachine.Interact.Reset','VirtualMachine.Interact.Suspend','VirtualMachine.Interact.GuestControl',
    'VirtualMachine.State.CreateSnapshot','VirtualMachine.State.RemoveSnapshot','VirtualMachine.State.RevertSnapshot',
    'Global.Diagnostics','Global.LogEvent','Global.ManageCustomFields','Global.SetCustomField'
)
# End of Settings

$Title          = "Horizon Service Account vCenter Privileges"
$Header         = "[count] required privilege(s) missing on the connecting vCenter user"
$Comments       = "Per VMware KB 88016 / Horizon Admin Guide. The Horizon-registered vCenter account needs the listed privileges to provision, refresh, recompose, push images, and manage instant clones. Missing privileges manifest as silent provisioning failures."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P1"
$Recommendation = "Apply the canonical 'Horizon Administrator' role at the vCenter root with Propagate=True. Reference: KB 88016."

if (-not $Global:VCConnected) { return }
$vc = $global:DefaultVIServer
if (-not $vc) { return }

# Resolve the connecting user's effective privileges at the root folder
$root = (Get-Folder -NoRecursion).ExtensionData | Select-Object -First 1
if (-not $root) { return }
$asm  = $vc.ExtensionData.Content.AuthorizationManager
try {
    $effective = $asm.FetchUserPrivilegeOnEntities(@($root.MoRef), $vc.User) | Select-Object -First 1
} catch {
    Write-Verbose "FetchUserPrivilegeOnEntities not available: $($_.Exception.Message)"
    return
}
if (-not $effective) { return }
$have = @{}
foreach ($p in $effective.Privileges) { $have[$p] = $true }

foreach ($p in $RequiredPrivileges) {
    if (-not $have.ContainsKey($p)) {
        [pscustomobject]@{
            Privilege = $p
            Status    = 'MISSING'
        }
    }
}

$TableFormat = @{ Status = { param($v,$row) 'bad' } }
