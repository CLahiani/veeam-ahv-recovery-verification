# User guide

[← Installation](installation.md) · [Configuration →](configuration.md) · 🇫🇷 [Version française](../fr/guide-utilisateur.md)

## How a run works

```
Step 0  PRE-FLIGHT   Authenticate to VBR (+ AHV plug-in API), Prism Central.
                     Check cluster / container / subnet exist, subnet is isolated,
                     no foreign VM on it, no leftover test VM.        → CP00–CP04
Step 1  RESTORE      For each VM: latest restore point, RPO check, full restore
                     to "<prefix><vm>" with every NIC remapped to the isolated
                     subnet, power on.                                → CP10–CP12
Step 2  VERIFY       Wait for the session (RTO), read VM state in Prism, enforce
                     NIC guardrail, wait for IP (NGT), ping, app checks. → CP13–CP30
Step 3  CLEANUP      Power off and delete the test VM (-Cleanup).     → CP40
Step 4  REPORT       HTML + CSV + JSON + transcript, exit code.
```

Restores are launched for all VMs first (Step 1), then verified one by one (Step 2), so several restores run in parallel on the appliance.

## Command line

```powershell
.\Test-AhvBackupRestore.ps1 [-VmNames] <string[]>
    [-ConfigPath <string>] [-Language en|fr]
    [-PingCheck] [-Cleanup] [-FailOnWarning] [-ReportDir <string>]
    [-VbrCredential <PSCredential>] [-AhvCredential <PSCredential>] [-PrismCredential <PSCredential>]
    [<configuration overrides>] [-WhatIf] [-Verbose]

.\Test-AhvBackupRestore.ps1 -InitConfig [-ConfigPath <string>]
```

### Main parameters

| Parameter | Description | Default |
|---|---|---|
| `-VmNames` | One or more **source VM names, exactly as shown in Veeam**. Position 0, so the name can be omitted. | — (required) |
| `-ConfigPath` | JSON configuration file. Command-line overrides win over the file. | `.\RecoveryVerification.json` |
| `-InitConfig` | Write a configuration template to `-ConfigPath` and exit. Asks before overwriting. | — |
| `-Language` | `en` or `fr` for console and reports. | System culture: `fr-*` → `fr`, otherwise `en` |
| `-PingCheck` | Enable **CP23** (ping the restored VM from this machine). Requires the probe to sit on the isolated subnet. | off |
| `-Cleanup` | **Delete the test VMs** at the end, and any leftover `RV-*` VM from a previous run during pre-flight. Without it, VMs are kept for analysis and CP40 is `SKIP`. | off |
| `-FailOnWarning` | Count `WARN` checkpoints as failures for the exit code and the per-VM result. | off |
| `-ReportDir` | Output folder for HTML / CSV / JSON / transcript. Created if missing. | `.\Reports` |
| `-WhatIf` | Show restore and delete actions without executing them. Pre-flight still runs. | — |

### Configuration overrides

Every value of the JSON file (except `AppChecks`) can be overridden for one run: `-VbrServer`, `-VbrPort`, `-VbrApiVersion`, `-AhvIntegrated`, `-AhvAppliance`, `-AhvApiVersion`, `-PrismCentral`, `-PrismPort`, `-TargetClusterName`, `-IsolatedNetworkName`, `-StorageContainerName`, `-VmNamePrefix`, `-MaxRestorePointAgeHours`, `-MaxRestoreMinutes`, `-BootTimeoutMinutes`. See [Configuration](configuration.md).

## Typical scenarios

### First run — validate the setup

```powershell
.\Test-AhvBackupRestore.ps1 -VmNames SRV-FILE01 -WhatIf -Verbose
```

Authenticates to VBR and Prism (plus the appliance in 12.x) and runs CP00–CP04. Nothing is restored. Fix any `KO` before going further. CP00's detail shows the mode in use (`VBR 13.x integrated plug-in (v9)` or `12.x appliance …`).

### Legacy VBR 12.x with the standalone appliance

```powershell
.\Test-AhvBackupRestore.ps1 -VmNames SRV-A -Cleanup -AhvIntegrated:$false -AhvAppliance veeam-ahv.local -AhvApiVersion v8 -VbrApiVersion 1.2-rev0
```

Or set `Veeam.AhvIntegrated: false` (with `AhvAppliance`, `AhvApiVersion: "v8"`, `VbrApiVersion: "1.2-rev0"`) in the JSON file. A third credential (appliance) is then prompted.

### Verify a couple of VMs, keep them for manual inspection

```powershell
.\Test-AhvBackupRestore.ps1 -VmNames SRV-AD01,SRV-FILE01 -PingCheck
```

Test VMs `RV-SRV-AD01` and `RV-SRV-FILE01` stay powered on in the isolated subnet. Connect to them through the Prism console. **Next run must use `-Cleanup`** or delete them manually, otherwise CP04 blocks.

### Full automated verification

```powershell
.\Test-AhvBackupRestore.ps1 -VmNames SRV-AD01,SRV-FILE01,SRV-SQL01 -PingCheck -Cleanup -FailOnWarning
if ($LASTEXITCODE -ne 0) { <# alert #> }
```

### Daily rotation over the whole estate

```powershell
$all    = Get-Content .\vms.txt              # one VM name per line
$d      = (Get-Date).DayOfYear
$sample = 0..2 | ForEach-Object { $all[($d * 3 + $_) % $all.Count] }
.\Test-AhvBackupRestore.ps1 -VmNames $sample -Cleanup
```

Three different VMs per day; the whole list is covered in `ceil(N/3)` days.

### Scheduled task (Windows)

```powershell
$action  = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-NoProfile -File C:\Tools\RecoveryVerification\Run.ps1'
$trigger = New-ScheduledTaskTrigger -Daily -At 06:00
Register-ScheduledTask -TaskName 'Veeam Recovery Verification AHV' -Action $action -Trigger $trigger -User 'DOMAIN\svc-rv' -Password '***'
```

Where `Run.ps1` retrieves credentials from a vault (see [Installation §4](installation.md#4-accounts)) and calls the script with `-Cleanup`.

## Reading the output

### Console

Each checkpoint prints one line:

```
  [CP11] OK   SRV-AD01         Restore point age <= 30 h - 9.4 h
  [CP13] WARN SRV-AD01         Restore duration <= 45 min - 51.2 min - RTO target exceeded
  [CP30] KO   SRV-WEB01        Application: Health - HTTP 503 https://10.99.0.12/health
  [CP23] SKIP SRV-FILE01       Ping from the probe - -PingCheck not enabled
```

Colours: green `OK`, red `KO`, yellow `WARN`, grey `SKIP`. A summary table per VM is printed at the end, followed by the paths of the four output files.

### Files in `-ReportDir`

| File | Content |
|---|---|
| `RecoveryVerification-<RunId>.html` | Banner (PASSED / PASSED WITH WARNINGS / FAILED), KPIs, summary per VM, full checkpoint table. Self-contained, share it as-is. |
| `RecoveryVerification-<RunId>.csv` | One row per checkpoint, `;`-delimited, UTF-8. For Excel / Power BI. |
| `RecoveryVerification-<RunId>.json` | RunId, date, language, target, thresholds, summary, checkpoints. For SIEM / monitoring ingestion. |
| `RecoveryVerification-<RunId>.log` | Full PowerShell transcript (use `-Verbose` for API URLs). |

`RunId` is `yyyyMMdd-HHmmss`.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | All checkpoints OK (or only WARN without `-FailOnWarning`). |
| `1` | At least one checkpoint `KO` (or `WARN` with `-FailOnWarning`). |
| `2` | Blocking pre-flight error (authentication, missing object, routed subnet, leftovers without `-Cleanup`) or unexpected fatal error. Reports are still produced. |

## Safety guardrails

- **CP02 (blocking)** — the target subnet must not be external and must have no gateway. Nothing is restored otherwise.
- **CP03** — any VM on the isolated subnet that does not start with the test prefix is reported (someone else is using the lab network).
- **CP04 (blocking)** — leftover test VMs from a previous run are deleted with `-Cleanup`, otherwise the run stops.
- **CP21 (guardrail)** — if a restored VM ends up with a NIC outside the isolated subnet, it is **powered off immediately**.
- **Restore never targets the original VM** (`restoreToOriginal = false`), the test VM has a distinct name (`<prefix><vm>`) and categories are not restored.
- Every API call has 3 retries on network / 5xx / 429 errors and produces a readable message with HTTP code and hint (401 credentials, 403 rights, 404 object / API version).

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| CP00 KO `HTTP 401` | Wrong credentials, or VBR API version header not accepted → `Veeam.VbrApiVersion` = `1.3-rev1` (13.x) / `1.2-rev0` (12.x). |
| CP00 KO `HTTP 404` on `/extension/…/api/v9/clusters` | 13.x mode against a 12.x server, or AHV plug-in not installed on the VBR server → check `AhvIntegrated`, or install the plug-in (Backup Infrastructure → Add Server → Nutanix AHV). |
| CP00 KO connection refused on appliance | `AhvIntegrated: false` against a 13.x environment where the appliance no longer exists → set `AhvIntegrated: true`, `AhvApiVersion: v9`. |
| CP01 KO `subnet '…' not found` | Network created in Prism but plug-in inventory not refreshed → rescan the Nutanix server in VBR (13.x) or in the appliance (12.x). |
| CP12 KO / CP13 WARN, restore slow to start (13.x) | Worker powered off or updating at session start; no worker on the target cluster (VBR borrows one from another cluster). Add a worker per cluster, disable the worker update check, raise `MaxRestoreMinutes`. |
| CP02 KO `is_external=True` or `gateway=…` | Subnet is routed. Recreate it as a plain non-routed VLAN without gateway. |
| CP04 KO `leftover VM(s)` | Previous run without `-Cleanup`. Rerun with `-Cleanup` or delete `RV-*` VMs in Prism. |
| CP10 KO `no Nutanix AHV restore point` | Name must match Veeam exactly (case-insensitive, but no wildcard). Check the VM is in an AHV backup job with at least one restore point. |
| CP12 KO `status = Failed` | Open the session in the Veeam console; typical causes: container full, name conflict, appliance disconnected from cluster. |
| CP22 WARN `no IP` | Nutanix Guest Tools not installed / not started in the guest, or OS still booting → raise `BootTimeoutMinutes`. |
| CP23 / CP30 SKIP | `-PingCheck` not set, or no IP, or no `AppChecks` entry for that VM. Probe must be on the isolated subnet. |
| CP30 SKIP `SqlServer module missing` | `Install-Module SqlServer`. |
| CP40 KO `delete '…' manually` | Prism refused the delete (rights, or VM still powering off). Delete it in Prism. |
| `HTTP 404` on plug-in calls | Wrong `Veeam.AhvApiVersion` (`v9` for 13.x, `v8` for the 12.x appliance). |

Lines tagged `# [API]` in the script are the ones most likely to need adjustment if a Veeam or Nutanix upgrade changes a response field name.
