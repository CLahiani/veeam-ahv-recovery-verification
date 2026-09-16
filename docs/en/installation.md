# Installation & prerequisites

[← README](../../README.md) · [User guide →](user-guide.md) · 🇫🇷 [Version française](../fr/installation.md)

## 1. Software

| Component | Requirement |
|---|---|
| Probe machine | Any **Linux or Windows** host with **Python 3.9+**. Standard library only for the core; optional `dnspython` / `ldap3` / `pymssql` for the Ldap / Dns / Sql checks (`pip install -r requirements.txt`). A small Linux VM is the natural choice. |
| Veeam Backup & Replication | REST API enabled (default port **9419**). `Veeam.VbrApiVersion` = `1.3-rev2` for VBR 13.1 (`1.3-rev1` for 13.0), `1.2-rev0` for 12.x. |
| Veeam Plug-in for Nutanix AHV | See [Veeam 13.x vs 12.x](#veeam-13x-integrated-plug-in-vs-12x-appliance) below. |
| Nutanix Prism Central | v3 API (default port **9440**). |
| Source VMs | **Nutanix Guest Tools** installed — the IP is read back from NGT (CP22); CP23 / CP30 depend on it. |

## Veeam 13.x (integrated plug-in) vs 12.x (appliance)

The way the tool talks to the AHV plug-in depends on your Veeam version. Set `Veeam.AhvIntegrated` accordingly (default `true`).

| | **VBR 13.x** — `AhvIntegrated: true` | **VBR 12.x** — `AhvIntegrated: false` |
|---|---|---|
| Architecture | Plug-in integrated into VBR; **workers** (lightweight Linux VMs deployed on the AHV cluster by VBR) move the data. No standalone appliance. | Standalone Veeam Plug-in for Nutanix AHV appliance (proxy VM). |
| Plug-in REST API base URL | `https://<VBR server>/extension/799a5a3e-ae1e-4eaf-86eb-8a9acc2670e2/api/v9` | `https://<appliance>/api/v8` |
| Authentication | **VBR OAuth token** reused. No third credential. | Appliance's own OAuth endpoint (`AHV_USER` / `AHV_PASSWORD`). |
| `AhvApiVersion` | `v9` | `v8` |
| `AhvAppliance` | Ignored | FQDN / IP of the appliance |
| Minimum versions | VBR **13.0.1.1071+**, plug-in **13.9.0.212+**, AOS **6.8.1.6+**, Prism Central pc.2022.6 – pc.2024.3.1.10 or **pc.7.3+** (pc.7.3.1.2, 7.3.1.3 and 7.5.0.0 excluded). iSCSI Data Services IP configured on the cluster. | Plug-in 6/7/8 per Veeam compatibility matrix. |

**Workers (13.x).** At least one AHV worker must be configured in VBR (*Backup Infrastructure → Backup Proxies → Add → Nutanix AHV worker*), ideally one per cluster. VBR powers the worker on when a restore session starts and off when it ends, so the first restore of a run can take a few extra minutes (worker boot, plus an optional update check that can be disabled in the worker properties). Account for this in `Thresholds.MaxRestoreMinutes`. The tool does not manage workers — VBR does.

**Endpoints.** `/clusters`, `/clusters/{id}/networks`, `/clusters/{id}/storageContainers`, `/restorePoints/restore`, `/sessions/{id}` are identical in v8 and v9. NIC discovery uses `/restorePoints/{id}/metadata` (v9) with automatic fallback to the deprecated `/networkAdapters` (v8). Restore points come from `GET /api/v1/restorePoints` (VBR 13) with fallback to `/objectRestorePoints` (VBR 12).

## 2. Network: the isolated subnet

Create in Prism a dedicated subnet that is a **VLAN not routed anywhere**, with **no default gateway** in its IPAM (or no IPAM), and **not marked external** (`is_external = false`). The tool verifies all three at every run (**CP02**, blocking) and refuses to restore anything otherwise.

Optionally enable Nutanix IPAM (DHCP) so restored VMs get an address; otherwise they keep their production static IP, which is fine in an isolated VLAN. Either way the IP is read from **NGT**. After creating the subnet, **rescan the Nutanix server in Veeam** (13.x: *Backup Infrastructure → Managed Servers*; 12.x: in the appliance) so CP01 finds it by name.

## 3. The probe machine

| Destination | Port | Purpose |
|---|---|---|
| VBR server | 9419/tcp | Restore points, authentication |
| VBR server (13.x) **or** AHV appliance (12.x) | 443/tcp | Launch and track restores via the plug-in REST API |
| Prism Central | 9440/tcp | Inspect VMs / subnets, power off, delete |
| Isolated subnet | ICMP, app ports | CP23 ping and CP30 application checks |

For the last line the probe needs a **second NIC attached to the isolated subnet**. Without it the tool still works; CP23 and CP30 are `SKIP`.

## 4. Accounts

| System | Minimum role | Secret keys |
|---|---|---|
| Veeam Backup & Replication | 13.x: a role allowed to **read restore points and start Nutanix AHV VM restores** (Veeam Restore Operator, or a scoped custom RBAC role from 13.1). 12.x: Veeam Restore Operator. | `VBR_USER`, `VBR_PASSWORD` |
| Veeam AHV appliance (**12.x only**) | Portal Administrator or Restore Operator. | `AHV_USER`, `AHV_PASSWORD` |
| Prism Central | **Cluster Admin** or a custom role with *view VM / subnet*, *update VM* (power off), *delete VM*. | `PRISM_USER`, `PRISM_PASSWORD` |

Secrets are read from `--secrets-file` (JSON, `chmod 600`), then environment variables, then interactive prompt. Never put them in `RecoveryVerification.json`.

## 5. Install

```bash
# Linux probe
sudo mkdir -p /opt/veeam-recovery-verification /var/lib/veeam-recovery-verification/reports
cd /opt/veeam-recovery-verification
# copy ahv_backup_restore.py, RecoveryVerification.sample.json, deploy/ (git clone or scp)
chmod +x ahv_backup_restore.py deploy/rotate-sample.sh
./ahv_backup_restore.py --init-config              # writes RecoveryVerification.json - edit it
cat > ~/.veeam-rv-secrets.json <<'EOF'
{ "VBR_USER": "svc-rv", "VBR_PASSWORD": "…", "PRISM_USER": "svc-rv", "PRISM_PASSWORD": "…" }
EOF
chmod 600 ~/.veeam-rv-secrets.json
./ahv_backup_restore.py -v SRV-A --secrets-file ~/.veeam-rv-secrets.json --dry-run --debug   # pre-flight only
```

```powershell
# Windows probe (Python 3 from python.org / winget)
py -3 ahv_backup_restore.py --init-config
py -3 ahv_backup_restore.py -v SRV-A --secrets-file C:\ProgramData\VeeamRV\secrets.json --dry-run
```

## 6. Schedule

- **Linux**: `deploy/veeam-recovery-verification-ahv.service` + `.timer` (systemd), or `deploy/rotate-sample.sh` for a daily rotation over `vms.txt`. `SuccessExitStatus=1 2` keeps the unit green when a verification fails; results live in the reports.
- **Windows**: `deploy/windows-scheduled-task.ps1` registers a daily Scheduled Task running `python.exe`.

## 7. TLS

REST calls skip certificate validation by default (self-signed VBR / Prism). Add `--verify-tls` once trusted certificates are in place.

## Next step

Read the [User guide](user-guide.md).
