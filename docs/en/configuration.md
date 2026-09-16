# Configuration reference

[← User guide](user-guide.md) · [Checkpoints →](checkpoints.md) · 🇫🇷 [Version française](../fr/configuration.md)

JSON file, `./RecoveryVerification.json` by default (`-c`). Generate with `--init-config` or copy `RecoveryVerification.sample.json`.

**Precedence:** built-in defaults ← JSON file ← command-line overrides. `AppChecks`, when present in the file, **replaces** the default one entirely. Keep the real file out of git (`.gitignore`); secrets never go in it.

## `Veeam`

| Key | CLI | Description | Default |
|---|---|---|---|
| `VbrServer` / `VbrPort` | `--vbr-server` / `--vbr-port` | VBR server and REST port. | `vbr.example.local` / `9419` |
| `VbrApiVersion` | `--vbr-api-version` | `x-api-version`: **`1.3-rev2` = 13.1**, `1.3-rev1` = 13.0, `1.2-rev0` = 12.x. | `1.3-rev2` |
| `AhvIntegrated` | `--ahv-integrated true|false` | **`true` = VBR 13.x** (plug-in integrated, workers, plug-in API served by VBR with the VBR token). **`false` = 12.x** standalone appliance. | `true` |
| `AhvAppliance` | `--ahv-appliance` | **12.x only**: appliance FQDN / IP. Ignored in 13.x. | `veeam-ahv.example.local` |
| `AhvApiVersion` | `--ahv-api-version` | Plug-in REST API version: **`v9` for 13.x**, `v8` for the 12.x appliance. | `v9` |

## `Nutanix`

| Key | CLI | Description | Default |
|---|---|---|---|
| `PrismCentral` / `PrismPort` | `--prism-central` / `--prism-port` | Prism Central (FQDN / IP) and API port. | `prism.example.local` / `9440` |

## `Target`

| Key | CLI | Description | Default |
|---|---|---|---|
| `ClusterName` | `--cluster-name` | AHV cluster receiving the test restores, **as named in the Veeam plug-in**. | `CLUSTER-01` |
| `IsolatedNetworkName` | `--isolated-network-name` | Isolated subnet name, identical in Prism and in the plug-in inventory (CP01, CP02). | `VLAN-RecoveryVerification` |
| `StorageContainerName` | `--storage-container-name` | Container for the restored disks; size it for your largest sample. | `default-container` |
| `VmNamePrefix` | `--vm-name-prefix` | Test VM names `<prefix><source>`; also identifies leftovers (CP03 / CP04). **Never** a prefix matching production VMs. | `RV-` |

## `Thresholds`

| Key | CLI | Description | Default |
|---|---|---|---|
| `MaxRestorePointAgeHours` | `--max-restore-point-age-hours` | **RPO target** — CP11 `KO` if older (daily job → 30 h). | `30` |
| `MaxRestoreMinutes` | `--max-restore-minutes` | **RTO target** — CP13 `WARN` if the restore session is longer. 13.x: include worker start-up. | `45` |
| `BootTimeoutMinutes` | `--boot-timeout-minutes` | Max wait for `ON` + NGT IP (CP20–CP22); also added to `MaxRestoreMinutes` as the session hard timeout. | `15` |
| `PollIntervalSeconds` | — | Polling interval. | `20` |

## `AppChecks`

Map **VM name → list of checks**; `"*"` applies to every VM and is merged with the VM list. One **CP30** per check, run **from the probe** against the NGT IP (CP22). `SKIP` when no IP or when the probe is not on the isolated subnet.

| Type | Fields | Passes when | Needs |
|---|---|---|---|
| `Tcp` | `Port` | TCP connect OK | — |
| `Http` | `Url` (with `{ip}`), `ExpectedStatus` (200) | expected status (TLS not validated, 15 s) | — |
| `Ldap` | `Port` | anonymous RootDSE bind OK — proves AD is up without credentials | `ldap3` |
| `Dns` | `Name`, `RecordType` (A) | `<ip>` answers the query | `dnspython` |
| `Sql` | `Port`, `Query`, `User`, `Password` | query returns a row (SQL login; integrated auth is not available from a non-domain probe) | `pymssql` |

```json
"AppChecks": {
  "*":         [ { "Type": "Tcp", "Port": 3389, "Label": "RDP (Windows)" } ],
  "SRV-AD01":  [ { "Type": "Ldap", "Port": 389, "Label": "LDAP" }, { "Type": "Dns", "Name": "example.local", "Label": "DNS zone" } ],
  "SRV-WEB01": [ { "Type": "Http", "Url": "https://{ip}/health", "ExpectedStatus": 200, "Label": "Health" } ],
  "SRV-SQL01": [ { "Type": "Sql", "Port": 1433, "Query": "SELECT COUNT(*) FROM sys.databases WHERE state_desc='ONLINE'", "User": "rv_check", "Password": "…", "Label": "Online DBs" } ]
}
```

Missing optional module → `SKIP` with the module name. Prefer credential-less checks (`Tcp`, `Http`, `Ldap`, `Dns`) for unattended runs; the restored VM is a clone in an isolated network where domain authentication may not work.

## Secrets

Order: `--secrets-file` (JSON, `chmod 600`) → environment (`VBR_USER`, `VBR_PASSWORD`, `PRISM_USER`, `PRISM_PASSWORD`, and `AHV_USER` / `AHV_PASSWORD` when `AhvIntegrated: false`) → interactive prompt.

## Report language

`-l en|fr` (or system locale) drives console strings, HTML labels and the `Language` field of the JSON report. CSV headers are technical and identical in both languages.
