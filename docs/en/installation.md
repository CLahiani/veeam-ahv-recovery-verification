# Installation & prerequisites

[← README](../../README.md) · [User guide →](user-guide.md) · 🇫🇷 [Version française](../fr/installation.md)

## 1. Software

| Component | Requirement |
|---|---|
| PowerShell | **7.2 or later** (`pwsh`). Windows PowerShell 5.1 is not supported (`SkipCertificateCheck`, ternary operator, `ConvertFrom-Json -AsHashtable`). |
| OS of the probe machine | Windows recommended. `Test-NetConnection` and `Resolve-DnsName` (used by Tcp / Ldap / Dns checks) are Windows cmdlets. On Linux, only Http and Sql checks work. |
| `SqlServer` module | Only if `Sql` application checks are defined: `Install-Module SqlServer -Scope CurrentUser` |
| Veeam Backup & Replication | REST API enabled (default port **9419**). Tested against API version header `1.2-rev0`; adjust `Veeam.VbrApiVersion` for your build. |
| Veeam Plug-in for Nutanix AHV | Appliance reachable over HTTPS; REST API prefix `v8` (or `v9`…) set in `Veeam.AhvApiVersion`. |
| Nutanix Prism Central | v3 API (default port **9440**). |

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
| VBR server | 9419/tcp | Find the latest restore points |
| Veeam AHV appliance | 443/tcp | Launch and track restores |
| Prism Central | 9440/tcp | Inspect VMs / subnets, power off, delete |
| Isolated subnet | ICMP, app ports | CP23 ping and CP30 application checks |

For the last line the probe needs a **second NIC attached to the isolated subnet**. If the probe is not on that subnet, the script still works: CP23 and CP30 are simply reported as `SKIP`.

## 4. Accounts

Three sets of credentials are requested at run time (or passed with `-VbrCredential`, `-AhvCredential`, `-PrismCredential`):

| System | Minimum role |
|---|---|
| Veeam Backup & Replication | **Veeam Restore Operator** (read restore points). |
| Veeam Plug-in for Nutanix AHV appliance | Account allowed to start a VM restore (Portal Administrator or Restore Operator). |
| Prism Central | **Cluster Admin** or a custom role with *view VM / subnet*, *update VM* (power off) and *delete VM*. |

Use dedicated service accounts. For unattended runs, store the credentials in a vault and retrieve them with [Microsoft.PowerShell.SecretManagement](https://github.com/PowerShell/SecretManagement):

```powershell
$vbr   = Get-Secret -Name RV-VBR   -AsPlainText:$false
$ahv   = Get-Secret -Name RV-AHV   -AsPlainText:$false
$prism = Get-Secret -Name RV-Prism -AsPlainText:$false
.\Test-AhvBackupRestore.ps1 -VmNames SRV-A -Cleanup -VbrCredential $vbr -AhvCredential $ahv -PrismCredential $prism
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

All API calls use `-SkipCertificateCheck` because Veeam and Nutanix appliances usually ship with self-signed certificates. If your appliances carry trusted certificates and you want strict validation, remove `SkipCertificateCheck = $true` in `Invoke-Api`, `Connect-Vbr` and `Connect-AhvAppliance`.

## Next step

Read the [User guide](user-guide.md).
