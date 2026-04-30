# AuthorityGate HealthCheck — Per-Platform Audit Account Setup

This document describes the **dedicated read-only service account per platform** model. Each platform that the audit touches gets its **own** account, scoped narrowly to that platform's read-only role. The accounts do not cross platforms; revoking one revokes nothing else.

This is the safest provisioning model:
- Compromise of one account exposes only one platform
- Each platform's admin team owns provisioning + teardown
- Audit logs cleanly attribute every read to the right team's audit identity
- Disable / delete is independent

---

## TL;DR — what to provision

| # | Identity | Lives on / Owned by | Access scope |
|---|---|---|---|
| 1 | `svc_audit_ad` | Active Directory | AD reads + DNS reads + DHCP reads only |
| 2 | `svc_audit_vcenter` | vCenter SSO (or AD source on SSO) | vCenter Read-only role at the root |
| 3 | `svc_audit_horizon` | Horizon Administrators directory | Horizon Administrators (Read only) |
| 4 | `svc_audit_appvol` | AppVol Manager local OR AD-bound | AppVol Auditors role |
| 5 | `svc_audit_nutanix` | Prism Central local user OR via IDP | AuthorityGate-HealthCheck-ReadOnly custom role |
| 6 | `svc_audit_veeam` | Veeam Backup user | Veeam Backup Viewer role |
| 7 | `svc_audit_uag` | UAG appliance | UAG admin (the existing local admin password) |
| 8 | `audit-vidm-client` (OAuth) | Workspace ONE Access | OAuth client_credentials, Admin Read scope |
| 9 | `svc_audit_uem` + Tenant API key | UEM Console | Read Only Admin role |
| 10 | `svc_audit_sql` | SQL Server logins | `db_datareader` on the specific backing DBs |

Each row is independent. If the customer doesn't have a backend, the corresponding account is skipped.

---

## Account 1 — Active Directory / DNS / DHCP audit account

### Identity
- **sAMAccountName**: `svc_audit_ad`
- **DisplayName**: `AuthorityGate AD Audit (Read-Only)`
- Place in your service-account OU
- PasswordNeverExpires per your service-account policy
- 24x7 logon hours

### AD permissions
- `Domain Users` (default)
- `DnsAdmins` — required for `Get-DnsServer*` RPC reads
- `DHCP Users` — read-only DHCP scopes / leases / options / audit log (NOT `DHCP Administrators`)
- One ACL grant: Read on `CN=Password Settings Container,CN=System,<your-domain-dn>` so Fine-Grained PSOs can be enumerated

### What it reads
- AD: privileged-group membership, KRBTGT password age, stale computer accounts, Default + Fine-Grained password policies, LAPS deployment, forest / domain functional levels, FSMO holders, replication state
- DNS: server settings, zones, conditional forwarders, recursion, root hints, stale-record audit
- DHCP: server inventory, scopes, leases, reservations, failover state, audit-log + database health, scope options

### Network
The runner host needs RPC reach (TCP/135 + dynamic high) to each DC, DNS server, and DHCP server.

---

## Account 2 — vCenter audit account

### Identity
Either a **vCenter SSO local user** (`svc_audit_vcenter@vsphere.local`) OR an AD user that vCenter SSO can resolve (if AD is configured as an SSO Identity Source).

### vCenter permissions
- Role: **Read-only**
- Bind point: vCenter root (Administration → Access Control → Global Permissions, or Administration → SSO → Users/Groups → Permissions)
- Propagate to children: yes

### What it reads
- Cluster + host inventory, VM inventory, datastore inventory, network inventory
- Performance metrics (Get-Stat) for the 30-day rollup peak plugins
- Snapshot trees, hardware versions, VMTools status
- Active alarms, recent events / failed tasks
- vCenter license inventory, ESXi build / patch state
- Per-host advanced settings (Hardening Guide audit)

### Network
Runner → vCenter on TCP/443 (HTTPS).

---

## Account 3 — Horizon audit account

### Identity
- AD user (e.g., `svc_audit_horizon`) OR the same identity bound directly via Horizon's Administrators interface
- Place in the customer's normal service-account OU

### Horizon permissions
- Role: **Administrators (Read only)**
- Scope: `Root` access group
- "Apply to subaccess groups" checked

### What it reads
- Connection Servers, gateways, pods, sites, federation
- Pools, farms, machines, sessions, events
- Authentication providers (RADIUS / SAML / TrueSSO / certs)
- Network ranges, access groups, restricted tags
- Helpdesk sessions (if Helpdesk plugin licensed)

### Network
Runner → each Connection Server on TCP/443.

---

## Account 4 — App Volumes audit account

### Identity
Either a local AppVol Manager user OR an AD user (AppVol can authenticate against AD if configured).

### AppVol permissions
- Role: **Auditors** (the read-only built-in role)
- Bind via AppVol Manager → Configuration → Administrators → Add → assign `Auditors`

### What it reads
- App package inventory + sync status, assignment + attachment tables
- Storage groups + datastores + capacity, writable volumes + capacity
- Active directory bindings, online sessions
- Activity log (recent errors), admin audit log

### Network
Runner → AppVol Manager on TCP/443.

---

## Account 5 — Nutanix Prism audit account

### Identity
Either a local Prism Central user OR an AD-federated user (if Prism is bound to your IDP).

### Nutanix permissions
- Custom role: **AuthorityGate-HealthCheck-ReadOnly**
- Use the role JSON shipped at `docs/Nutanix-ReadOnly-Role.json` (12 read-only permissions)
- Bind at scope **All clusters** (not a Project)

The 12 permissions: `view_cluster`, `view_host`, `view_vm`, `view_storage_container`, `view_subnet`, `view_vm_snapshot`, `view_alert`, `view_audit`, `view_task`, `view_protection_rule`, `view_recovery_plan`, `view_lcm_entities`.

### What it reads
- Cluster + host + VM + storage container + subnet inventory
- 30-day perf rollups for hosts and storage containers
- Alerts (24h), audit (7d), failed tasks (24h)
- DR posture (protection rules + recovery plans)
- LCM firmware currency
- Cluster headroom (N+1) modeling

### Network
Runner → Prism Central / Element on TCP/9440.

---

## Account 6 — Veeam audit account

### Identity
A Veeam Backup user (local Veeam OR AD-bound).

### Veeam permissions
- Role: **Veeam Backup Viewer** (read-only)
- Bind via Veeam Console → Users and Roles → Add

### What it reads
- Backup job inventory + last-run results + age
- Repository capacity + states
- Per-VM protected status, recent restore points
- Veeam license + edition + expiry

### Network
Runner → Veeam B&R on TCP/9419.

---

## Account 7 — UAG admin (local-only, irreducible)

UAG admin is appliance-local — there is no role / RBAC, no LDAP federation. Provide:
- The existing UAG admin password (or rotate for the engagement)
- One value per appliance if the customer's UAGs have different passwords

### What it reads
- System settings, edge service settings (View, Tunnel, Web Reverse Proxy, Content Gateway)
- Auth methods (SAML, RADIUS, Cert, RSA, OAuth)
- Network configuration (NICs, routes, DNS, NTP)
- Live monitor stats (CPU/Mem/Disk/sessions)

### Network
Runner → UAG on TCP/9443.

---

## Account 8 — Workspace ONE Access (vIDM) OAuth client

vIDM REST API uses OAuth `client_credentials` grant — Client ID + Shared Secret, NOT a user. Create a dedicated audit client:

- Catalog → Settings → Remote App Access → Create Client
- Access Type: **Service Client Token**
- Client ID: `audit-vidm-client`
- Scope: **Admin Read**
- Token Type: Bearer
- Generate Shared Secret

### What it reads
- Tenant version + health, connector inventory, directory bindings
- Application catalog, access policies, auth methods
- Recent events (last 24h)

### Network
Runner → vIDM on TCP/443.

---

## Account 9 — Workspace ONE UEM admin + Tenant API Key

UEM REST API needs **two secrets**: a console admin user/password AND the per-tenant API key (`aw-tenant-code` header).

- Create a UEM admin user `svc_audit_uem` with role **Read Only Admin**
- Pull the tenant API key from UEM Console → All Settings → System → Advanced → API → REST API

### What it reads
- Device inventory + per-OG hierarchy, smart groups, MDM profiles
- Managed apps (internal / public / purchased)
- Compliance policies + state, recent enrollments

### Network
Runner → UEM Console on TCP/443.

---

## Account 10 — SQL Server backing-DB audit account

Each backing DB (Horizon Event DB, App Volumes DB, vCenter legacy DB) needs an account with READ rights on that database only.

### Identity
Either an AD user `svc_audit_sql` OR a SQL-auth login. AD-auth is preferred for credential rotation.

### SQL permissions
- Login: `DOMAIN\svc_audit_sql` (or SQL login)
- Role: `db_datareader` on each backing database — **NOT** `sysadmin`
- Apply per-database via SSMS → Security → Logins → Properties → User Mapping

### What it reads
- DB state, size, log size, free space, recovery model
- Last successful backup timestamp + age (`msdb.dbo.backupset`)

### Network
Runner → SQL Server on TCP/1433 (or named-instance dynamic port).

---

## Pre-flight checklist (per-platform owners run their own row)

For each platform you authorize:

- [ ] Account exists with the documented sAMAccountName / role binding
- [ ] Permissions are exactly as listed (no Domain Admin, no `sysadmin`, no Backup Administrator)
- [ ] Network: runner → backend port reachable
- [ ] Account is **not** locked out
- [ ] Password not expired

---

## Engagement-end teardown

Each platform owner runs their own teardown — independent of every other platform.

```text
AD:        Disable-ADAccount svc_audit_ad; remove from DnsAdmins + DHCP Users
vCenter:   Remove the Read-only role binding
Horizon:   Remove the Administrators (Read only) binding
AppVol:    Delete the Auditors role binding
Nutanix:   Delete the AuthorityGate-HealthCheck-ReadOnly role binding
Veeam:     Delete the Veeam Backup Viewer binding
UAG:       Rotate the admin password
vIDM:      Delete the OAuth client (Catalog -> Settings -> Remote App Access)
UEM:       Disable the audit admin + rotate the tenant API key if it was issued for the engagement
SQL:       DROP USER svc_audit_sql on each backing DB; DROP LOGIN
```

No shared identity means no orphaned cross-platform access after teardown.

---

## Why per-platform instead of one unified AD account?

| Concern | Per-platform model | Single AD account model |
|---|---|---|
| Compromise blast radius | Limited to one platform | Spans every federated platform |
| Audit-log attribution | Clear: each platform's audit log shows its own audit user | Same identity in every system; harder to tell apart |
| Provisioning ownership | Each team owns their account end-to-end | Identity team provisions; every platform owner reviews bindings |
| Teardown | Each platform deletes independently — no orphan paths | Disable in AD, then chase down every platform binding |
| Compliance / SoX | Easy to map "who reads what" per platform | Single user across systems triggers reviewer questions |

The per-platform model takes ~10 extra minutes to provision but is cleaner for security review.
