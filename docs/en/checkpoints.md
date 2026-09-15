# Checkpoints reference

[← Configuration](configuration.md) · [README](../../README.md) · 🇫🇷 [Version française](../fr/points-de-controle.md)

Every check is recorded as a **checkpoint** with a status `OK`, `KO`, `WARN` or `SKIP`, and appears in the console, the CSV / JSON files and the HTML report. `Value` holds the measured figure for CP11 (hours) and CP13 (minutes).

**Blocking** checkpoints stop the run in pre-flight (exit code 2). Others continue; a `KO` on a VM skips the remaining checks for that VM only.

## Step 0 — Pre-flight (once per run)

| CP | Check | OK | WARN | KO | Blocking |
|---|---|---|---|---|---|
| **CP00** | Authentication to VBR, AHV appliance, Prism Central | 3 tokens obtained | — | Any login failed (HTTP 401 / network) | ✔ |
| **CP01** | Cluster, storage container and isolated subnet exist in the appliance inventory | All three found by name | — | One is missing (`Detail` says which) | ✔ |
| **CP02** | Isolated subnet is **not routed** (Prism: `is_external = false`, no default gateway) | Both conditions true | — | Subnet not found in Prism, or external, or has a gateway | ✔ |
| **CP03** | No foreign VM on the isolated subnet | No VM, or only `<prefix>*` VMs | — | VMs not starting with the prefix are attached (listed) | — |
| **CP04** | No leftover test VM (`<prefix>*`) from a previous run | None | Leftovers found **and deleted** (`-Cleanup`) | Leftovers found without `-Cleanup`, or deletion failed | ✔ |

## Step 1 — Restore (per VM)

| CP | Check | OK | WARN | KO | SKIP |
|---|---|---|---|---|---|
| **CP10** | Latest Nutanix AHV restore point found in VBR (exact name match) | Found, `Detail` = creation time | — | No restore point → remaining CPs `SKIP` | — |
| **CP11** | Restore point age ≤ `MaxRestorePointAgeHours` (**RPO**) | Age within target | — | Older than target (`RPO missed, check the backup job`) | — |
| **CP12** | Restore session started and completed with `Success` / `Warning` | `Success` | `Warning` | Launch failed, `Failed`, or `Timeout` after `MaxRestoreMinutes + BootTimeoutMinutes` → remaining CPs `SKIP` | `-WhatIf` |

## Step 2 — Verify (per VM)

| CP | Check | OK | WARN | KO | SKIP |
|---|---|---|---|---|---|
| **CP13** | Restore duration ≤ `MaxRestoreMinutes` (**RTO**) | Within target | Exceeded (`RTO target exceeded`) | — | Restore failed |
| **CP20** | Test VM found in Prism and `power_state = ON` | `ON` | — | VM not found, or not `ON` after `BootTimeoutMinutes` | Restore failed |
| **CP21** | **Guardrail** — every NIC of the test VM is on the isolated subnet | All NICs on the isolated subnet | No NIC attached although the source had some | A NIC is on another subnet → **VM powered off immediately** | Restore failed |
| **CP22** | IP address reported by Nutanix Guest Tools | IP present (`Detail` = IP) | VM is `ON` but no IP (NGT missing, no DHCP, OS still booting) | VM not `ON` and no IP | Restore failed |
| **CP23** | Ping from the probe (`-PingCheck`) | 2 echo replies | — | No reply | `-PingCheck` off, or no IP |
| **CP30** | Application checks — **one checkpoint per check** (`Application: <Label>`) | Check passed | — | Check failed (`Detail` = reason) | No IP, no check defined, `SqlServer` module missing, unknown type |

## Step 3 — Cleanup (per VM, always attempted)

| CP | Check | OK | KO | SKIP |
|---|---|---|---|---|
| **CP40** | Test VM powered off and deleted (`-Cleanup`) | Deleted | Deletion failed (`delete '…' manually in Prism`) | `-Cleanup` off (VM kept), or VM never found |

## Per-VM result and exit code

| Situation | Per-VM `Result` | Exit code |
|---|---|---|
| No `KO`, no `WARN` | `OK` | `0` |
| `WARN` only, without `-FailOnWarning` | `OK (warnings)` | `0` |
| `WARN` only, with `-FailOnWarning` | `KO` | `1` |
| Any `KO` | `KO` | `1` |
| Blocking pre-flight failure or fatal error | — | `2` |

## Mapping to audit questions

| Audit question | Evidence |
|---|---|
| Backups exist and respect the RPO | CP10 + CP11 with `Value` (hours) in CSV / JSON |
| Backups are restorable within the RTO | CP12 + CP13 with `Value` (minutes) |
| Restored systems boot and are reachable | CP20 + CP22 + CP23 |
| Applications work after restore | CP30 per service |
| Tests never expose production | CP02 + CP03 + CP21 |
| Test environment is cleaned | CP04 + CP40 |

Keep the HTML report (and optionally the CSV) of each run as evidence; the `RunId` in the filename ties the four files together.
