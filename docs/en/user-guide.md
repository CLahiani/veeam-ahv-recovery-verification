# User guide

[← Installation](installation.md) · [Configuration →](configuration.md) · 🇫🇷 [Version française](../fr/guide-utilisateur.md)

## How a run works

```
Step 0  PRE-FLIGHT   Authenticate to VBR (+ AHV plug-in API), Prism Central. Cluster / container /
                     subnet exist, subnet is isolated, no foreign VM, no leftover test VM.   → CP00–CP04
Step 1  RESTORE      For each VM: latest restore point, RPO check, full restore to "<prefix><vm>"
                     with every NIC remapped to the isolated subnet, power on.               → CP10–CP12
Step 2  VERIFY       Wait for the session (RTO), VM state in Prism, NIC guardrail, NGT IP, ping,
                     application checks from the probe.                                       → CP13–CP30
Step 3  CLEANUP      Power off and delete the test VM (--cleanup).                            → CP40
Step 4  REPORT       HTML + CSV + JSON + log, exit code.
```

Restores are launched for all VMs first (Step 1), then verified one by one (Step 2), so several restores run in parallel on the plug-in.

## Command line

```
ahv_backup_restore.py -v NAME [-v NAME ...] [-c CONFIG] [-l en|fr] [--cleanup] [--ping-check] [--fail-on-warning]
                      [--report-dir DIR] [--secrets-file FILE] [--verify-tls] [-n|--dry-run] [--debug]
                      [configuration overrides]
ahv_backup_restore.py --init-config [--force] [-c CONFIG]
```

| Option | Description | Default |
|---|---|---|
| `-v`, `--vm NAME` | Source VM name **exactly as shown in Veeam**. Repeat for several VMs. | required |
| `-c`, `--config` | JSON configuration file. | `./RecoveryVerification.json` |
| `--init-config` / `--force` | Write the configuration template (overwrite with `--force`) and exit. | — |
| `-l`, `--language` | `en` or `fr` for console and reports. | system locale |
| `--ping-check` | Enable CP23 (ping from the probe; needs a NIC on the isolated subnet). | off |
| `--cleanup` | **Delete the test VMs** at the end, and leftover `<prefix>*` VMs in pre-flight. Without it VMs are kept and CP40 is `SKIP`. | off |
| `--fail-on-warning` | Count `WARN` as failure for the exit code. | off |
| `--report-dir` | Output folder for reports and log. | `./Reports` |
| `--secrets-file` | JSON with `VBR_USER`, `VBR_PASSWORD`, `PRISM_USER`, `PRISM_PASSWORD` (+ `AHV_USER`, `AHV_PASSWORD` for 12.x). Env vars and prompt are the fallbacks. | — |
| `--verify-tls` | Validate certificates. | off |
| `-n`, `--dry-run` | Pre-flight runs for real; restore / delete are only displayed. | — |
| `--debug` | Echo the debug log (REST calls) to the console. | — |

Configuration overrides: `--vbr-server --vbr-port --vbr-api-version --ahv-integrated true|false --ahv-appliance --ahv-api-version --prism-central --prism-port --cluster-name --isolated-network-name --storage-container-name --vm-name-prefix --max-restore-point-age-hours --max-restore-minutes --boot-timeout-minutes`.

## Typical scenarios

```bash
# first run - validate the setup (CP00-CP04), nothing is restored; CP00's detail shows the mode (13.x integrated / 12.x appliance)
./ahv_backup_restore.py -v SRV-FILE01 --secrets-file ~/.veeam-rv-secrets.json --dry-run --debug

# legacy VBR 12.x with the standalone appliance
./ahv_backup_restore.py -v SRV-A --cleanup --ahv-integrated false --ahv-appliance veeam-ahv.local --ahv-api-version v8 --vbr-api-version 1.2-rev0

# restore two VMs and keep them for manual inspection (Prism console) - next run must use --cleanup, otherwise CP04 blocks
./ahv_backup_restore.py -v SRV-AD01 -v SRV-FILE01 --ping-check --secrets-file ~/.veeam-rv-secrets.json

# full automated verification
./ahv_backup_restore.py -v SRV-AD01 -v SRV-FILE01 -v SRV-SQL01 --ping-check --cleanup --fail-on-warning --secrets-file ~/.veeam-rv-secrets.json
echo $?      # 0 OK, 1 checkpoint failed, 2 pre-flight / fatal

# daily rotation of 3 VMs from vms.txt: deploy/rotate-sample.sh + systemd timer (Linux) or deploy/windows-scheduled-task.ps1
```

## Reading the output

```
  [CP00] OK   -                Authentication VBR / AHV plug-in / Prism Central - VBR 13.x integrated plug-in (v9)
  [CP11] OK   SRV-AD01         Restore point age <= 30 h - 9.4 h
  [CP13] WARN SRV-AD01         Restore duration <= 45 min - 51.2 min - RTO target exceeded
  [CP30] KO   SRV-WEB01        Application: Health - HTTP 503 https://10.99.0.12/health
```

| File in `--report-dir` | Content |
|---|---|
| `RecoveryVerification-<RunId>.html` | Banner, KPIs, summary per VM, checkpoint table. Self-contained. |
| `RecoveryVerification-<RunId>.csv` | One row per checkpoint, `;`-delimited, UTF-8. |
| `RecoveryVerification-<RunId>.json` | RunId, `Platform: NutanixAHV`, `Method: FullRestoreToIsolatedSubnet`, target, thresholds, summary, checkpoints. |
| `RecoveryVerification-<RunId>.log` | Debug log: REST calls, tracebacks. |

Exit codes: `0` all OK · `1` at least one `KO` (or `WARN` with `--fail-on-warning`) · `2` blocking pre-flight or fatal error (reports still produced).

## Safety guardrails

- **CP02 (blocking)** — the target subnet must not be external and must have no gateway.
- **CP03** — any non-test VM on the isolated subnet is reported.
- **CP04 (blocking)** — leftover test VMs are deleted with `--cleanup`, otherwise the run stops.
- **CP21 (guardrail)** — a restored VM with a NIC outside the isolated subnet is **powered off immediately**.
- Restore never targets the original VM (`restoreToOriginal = false`), the test VM has a distinct name, categories are not restored.
- REST calls retry 3× on network / 5xx / 429 and report readable errors (401 credentials, 403 rights, 404 object / API version).

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| CP00 KO `HTTP 401` | Wrong credentials, or `VbrApiVersion` not accepted (`1.3-rev2` 13.1 / `1.2-rev0` 12.x). |
| CP00 KO `HTTP 404` on `/extension/…/api/v9/clusters` | 13.x mode against a 12.x server, or AHV plug-in not installed on VBR → check `AhvIntegrated`, install the plug-in. |
| CP00 KO connection refused on appliance | `AhvIntegrated: false` against a 13.x environment (appliance gone) → `AhvIntegrated: true`, `AhvApiVersion: v9`. |
| CP01 KO `subnet '…' not found` | Network created in Prism but plug-in inventory not refreshed → rescan the Nutanix server in VBR (13.x) / appliance (12.x). |
| CP02 KO `is_external=True` or `gateway=…` | Subnet is routed. Recreate it as a plain non-routed VLAN without gateway. |
| CP04 KO `leftover VM(s)` | Previous run without `--cleanup`. Rerun with `--cleanup` or delete `<prefix>*` VMs in Prism. |
| CP10 KO `no Nutanix AHV restore point` | Exact Veeam name required; VM must be in an AHV backup job with a restore point. |
| CP12 KO `status = Failed` | Open the session in the Veeam console: container full, name conflict, worker / appliance disconnected. |
| CP12 KO / CP13 WARN, slow start (13.x) | Worker powered off or updating; no worker on the target cluster. Add a worker per cluster, disable the worker update check, raise `MaxRestoreMinutes`. |
| CP22 WARN `no IP` | NGT not installed / not started, or OS still booting → raise `BootTimeoutMinutes`. |
| CP23 / CP30 SKIP | `--ping-check` off, no IP, no `AppChecks` entry, or probe not on the isolated subnet. |
| CP30 SKIP `python module … missing` | `pip install dnspython ldap3 pymssql` (or `-r requirements.txt`). |
| CP40 KO | Prism refused the delete (rights, VM still powering off). Delete it in Prism. |
| `HTTP 404` on plug-in calls | Wrong `AhvApiVersion` (`v9` 13.x / `v8` 12.x). |
