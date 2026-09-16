# Installation & prerequisites

[← README](../../README.md) · [User guide →](user-guide.md) · 🇫🇷 [Version française](../fr/installation.md)

## 1. Software

| Component | Requirement |
|---|---|
| PowerShell | **7.2 or later** (`pwsh`). Windows PowerShell 5.1 is not supported (`SkipCertificateCheck`, ternary operator, `ConvertFrom-Json -AsHashtable`). |
| OS of the probe machine | Windows recommended. `Test-NetConnection` and `Resolve-DnsName` (used by Tcp / Ldap / Dns checks) are Windows cmdlets. On Linux, only Http and Sql checks work. |
| `SqlServer` module | Only if `Sql` application checks are defined: `Install-Module SqlServer -Scope CurrentUser` |
| Veeam Backup & Replication | REST API enabled (default port **9419**). `Veeam.VbrApiVersion` = `1.3-rev2` for VBR 13.1 (`1.3-rev1` for 13.0), `1.2-rev0` for 12.x. |
| Veeam Plug-in for Nutanix AHV | See [Veeam 13.x vs 12.x](#veeam-13x-integrated-plug-in-vs-12x-appliance) below. |
| Nutanix Prism Central | v3 API (default port **9440**). |

## Veeam 13.x (integrated plug-in) vs 12.x (appliance)

The way the script talks to the AHV plug-in depends on your Veeam version. Set `Veeam.AhvIntegrated` accordingly (default `true`).

| | **VBR 13.x** — `AhvIntegrated: true` | **VBR 12.x** — `AhvIntegrated: false` |
|---|---|---|
| Architecture | Plug-in integrated into VBR; **workers** (lightweight Linux VMs deployed on the AHV cluster by VBR) move the data. No standalone appliance. | Standalone Veeam Plug-in for Nutanix AHV appliance (proxy VM). |
| Plug-in REST API base URL | `https://<VBR server>/extension/799a5a3e-ae1e-4eaf-86eb-8a9acc2670e2/api/v9` | `https://<appliance>/api/v8` |
| Authentication | **VBR OAuth token** reused (`/api/oauth2/token` on port 9419). No third credential. | Appliance's own OAuth endpoint (`-AhvCredential`). |
| `AhvApiVersion` | `v9` | `v8` |
| `AhvAppliance` | Ignored | FQDN / IP of the appliance |
| Minimum versions | VBR **13.0.1.1071+**, plug-in **13.9.0.212+**, AOS **6.8.1.6+**, Prism Central pc.2022.6 – pc.2024.3.1.10 or **pc.7.3+** (pc.7.3.1.2, 7.3.1.3 and 7.5.0.0 are excluded). iSCSI Data Services IP configured on the cluster. | Plug-in 6/7/8 per Veeam compatibility matrix. |

**Workers (13.x).** At least one AHV worker must be configured in VBR (*Backup Infrastructure → Backup Proxies → Add → Nutanix AHV worker*), ideally one per cluster. VBR powers the worker on when a restore session starts and off when it ends, so the first restore of a run can take a few extra minutes (worker boot, plus an optional update check that can be disabled in the worker properties). Account for this in `Thresholds.MaxRestoreMinutes`. The script does not manage workers — VBR does.

**Endpoints.** The plug-in endpoints used by the script (`/clusters`, `/clusters/{id}/networks`, `/clusters/{id}/storageContainers`, `/restorePoints/restore`, `/sessions/{id}`) are identical in v8 and v9. The only difference is NIC discovery: v9 uses `/restorePoints/{id}/metadata` (v8's `/networkAdapters` is deprecated); the script tries `metadata` first and falls back automatically.

## 2. Network: the isolated subnet

This is the safety foundation of the whole process. Create in Prism a dedicated subnet that is:

- a **VLAN not routed anywhere** (no L3 interface on the core switch);
- with **no default gateway** in its IPAM configuration (or no IPAM at all);
- **not marked external** (`is_external = false`).

The script verifies these three points at every run (checkpoint **CP02**, blocking) and refuses to restore anything if the subnet looks routed.

Optionally enable Nutanix IPAM (DHCP) on the subnet so restored VMs receive an address; otherwise they keep their static IP from production, which is fine because the VLAN is isolated. Either way, the IP is read back from **Nutanix Guest Tools** (CP22), so NGT must be installed in the source VMs for CP22 / CP23 / CP30 to pass.

After creating the subnet, **rescan the cluster in the Veeam AHV appliance** so the network appears in its inventory (checkpoint **CP01** looks it up by name).

## 3. The probe machine

The script must run from a machine that can reach:

| Destination | Port | Purpose |
|---|---|---|
| VBR server | 9419/tcp | Find the latest restore points, authenticate |
| VBR server (13.x) **or** AHV appliance (12.x) | 443/tcp | Launch and track restores via the plug-in REST API |
| Prism Central | 9440/tcp | Inspect VMs / subnets, power off, delete |
| Isolated subnet | ICMP, app ports | CP23 ping and CP30 application checks |

For the last line the probe needs a **second NIC attached to the isolated subnet**. If the probe is not on that subnet, the script still works: CP23 and CP30 are simply reported as `SKIP`.

## 4. Accounts

Credentials are requested at run time (or passed with `-VbrCredential`, `-PrismCredential`, and `-AhvCredential` for 12.x):

| System | Minimum role |
|---|---|
| Veeam Backup & Replication | 13.x: a role allowed to **read restore points and start Nutanix AHV VM restores** (Veeam Restore Operator, or a scoped custom RBAC role introduced in 13.1). 12.x: Veeam Restore Operator. |
| Veeam Plug-in for Nutanix AHV appliance (**12.x only**) | Account allowed to start a VM restore (Portal Administrator or Restore Operator). |
| Prism Central | **Cluster Admin** or a custom role with *view VM / subnet*, *update VM* (power off) and *delete VM*. |

Use dedicated service accounts. For unattended runs, store the credentials in a vault and retrieve them with [Microsoft.PowerShell.SecretManagement](https://github.com/PowerShell/SecretManagement):

```powershell
$vbr   = Get-Secret -Name RV-VBR   -AsPlainText:$false
$prism = Get-Secret -Name RV-Prism -AsPlainText:$false
.\Test-AhvBackupRestore.ps1 -VmNames SRV-A -Cleanup -VbrCredential $vbr -PrismCredential $prism
# 12.x: add  -AhvCredential (Get-Secret -Name RV-AHV -AsPlainText:$false)
```

## 5. Install the script

1. Copy `Test-AhvBackupRestore.ps1` and `RecoveryVerification.sample.json` into a folder on the probe, e.g. `C:\Tools\RecoveryVerification\`.
2. Unblock the file if it was downloaded: `Unblock-File .\Test-AhvBackupRestore.ps1`.
3. Generate the configuration template and fill it in:

   ```powershell
   .\Test-AhvBackupRestore.ps1 -InitConfig
   notepad .\RecoveryVerification.json
   ```

   Alternatively, copy the sample: `Copy-Item RecoveryVerification.sample.json RecoveryVerification.json`.
4. Run a dry run to validate connectivity and configuration without restoring anything:

   ```powershell
   .\Test-AhvBackupRestore.ps1 -VmNames SRV-A -WhatIf -Verbose
   ```

   Pre-flight checkpoints CP00–CP04 run for real; restore actions are only displayed.

## 6. TLS certificates

All API calls use `-SkipCertificateCheck` because Veeam and Nutanix components usually ship with self-signed certificates. If they carry trusted certificates and you want strict validation, remove `SkipCertificateCheck = $true` in `Invoke-Api`, `Connect-Vbr` and `Connect-AhvAppliance`.

## Next step

Read the [User guide](user-guide.md).
