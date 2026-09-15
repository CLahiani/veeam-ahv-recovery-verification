# Configuration reference

[← User guide](user-guide.md) · [Checkpoints →](checkpoints.md) · 🇫🇷 [Version française](../fr/configuration.md)

Configuration is a JSON file, `.\RecoveryVerification.json` by default (`-ConfigPath` to change). Generate a template with `-InitConfig` or copy `RecoveryVerification.sample.json`.

**Precedence:** built-in defaults ← JSON file ← command-line parameters. Every key is optional; missing keys fall back to defaults. The `AppChecks` section, when present in the file, **replaces** the default one entirely.

> Keep `RecoveryVerification.json` out of source control (it is in `.gitignore`): it contains your server names. Commit only the `.sample.json`.

## Full example

```json
{
  "Veeam": {
    "VbrServer": "vbr.example.local",
    "VbrPort": 9419,
    "VbrApiVersion": "1.2-rev0",
    "AhvAppliance": "veeam-ahv.example.local",
    "AhvApiVersion": "v8"
  },
  "Nutanix": {
    "PrismCentral": "prism.example.local",
    "PrismPort": 9440
  },
  "Target": {
    "ClusterName": "CLUSTER-01",
    "IsolatedNetworkName": "VLAN-RecoveryVerification",
    "StorageContainerName": "default-container",
    "VmNamePrefix": "RV-"
  },
  "Thresholds": {
    "MaxRestorePointAgeHours": 30,
    "MaxRestoreMinutes": 45,
    "BootTimeoutMinutes": 15,
    "PollIntervalSeconds": 20
  },
  "AppChecks": {
    "*":         [ { "Type": "Tcp", "Port": 3389, "Label": "RDP (Windows)" } ],
    "SRV-AD01":  [ { "Type": "Ldap", "Port": 389, "Label": "LDAP" },
                   { "Type": "Dns",  "Name": "example.local", "Label": "DNS zone" },
                   { "Type": "Tcp",  "Port": 88, "Label": "Kerberos" } ],
    "SRV-FILE01": [ { "Type": "Tcp", "Port": 445, "Label": "SMB" } ],
    "SRV-WEB01": [ { "Type": "Http", "Url": "https://{ip}/health", "ExpectedStatus": 200, "Label": "Health endpoint" } ],
    "SRV-SQL01": [ { "Type": "Sql", "Port": 1433, "Query": "SELECT COUNT(*) FROM sys.databases WHERE state_desc='ONLINE'", "Label": "Online databases" } ]
  }
}
```

## `Veeam`

| Key | CLI override | Description | Default |
|---|---|---|---|
| `VbrServer` | `-VbrServer` | Veeam Backup & Replication server (FQDN or IP). | `vbr.example.local` |
| `VbrPort` | `-VbrPort` | VBR REST API port. | `9419` |
| `VbrApiVersion` | — | Value of the `x-api-version` header. Must match your VBR build (see the REST API reference for your version). | `1.2-rev0` |
| `AhvAppliance` | `-AhvAppliance` | Veeam Plug-in for Nutanix AHV appliance (FQDN or IP, HTTPS 443). | `veeam-ahv.example.local` |
| `AhvApiVersion` | `-AhvApiVersion` | API prefix of the appliance: `v8`, `v9`… | `v8` |

## `Nutanix`

| Key | CLI override | Description | Default |
|---|---|---|---|
| `PrismCentral` | `-PrismCentral` | Prism Central (FQDN or IP). | `prism.example.local` |
| `PrismPort` | `-PrismPort` | Prism API port. | `9440` |

## `Target`

| Key | CLI override | Description | Default |
|---|---|---|---|
| `ClusterName` | `-TargetClusterName` | AHV cluster receiving the test restores, **as named in the Veeam appliance**. | `CLUSTER-01` |
| `IsolatedNetworkName` | `-IsolatedNetworkName` | Name of the isolated subnet, identical in Prism and in the appliance inventory. Checked by CP01 and CP02. | `VLAN-RecoveryVerification` |
| `StorageContainerName` | `-StorageContainerName` | Storage container for the restored disks. Size it for your largest sample. | `default-container` |
| `VmNamePrefix` | `-VmNamePrefix` | Prefix of test VMs (`<prefix><source name>`). Also used by CP03 / CP04 to recognise test VMs — **never** use a prefix that matches production VMs. | `RV-` |

## `Thresholds`

| Key | CLI override | Description | Default |
|---|---|---|---|
| `MaxRestorePointAgeHours` | `-MaxRestorePointAgeHours` | **RPO target.** CP11 is `KO` if the latest restore point is older. Set it to your backup interval plus margin (daily job → 30 h). | `30` |
| `MaxRestoreMinutes` | `-MaxRestoreMinutes` | **RTO target.** CP13 is `WARN` if the restore session takes longer. | `45` |
| `BootTimeoutMinutes` | `-BootTimeoutMinutes` | Max wait for the VM to be `ON` and report an IP through NGT (CP20–CP22). Also added to `MaxRestoreMinutes` as the hard timeout of the restore session. | `15` |
| `PollIntervalSeconds` | — | Polling interval for session and VM state. | `20` |

## `AppChecks`

A map **VM name → list of checks**. The special key `"*"` applies to every VM and is merged with the VM-specific list. Each check produces one **CP30** checkpoint labelled `Application: <Label>` (or `<Type>` if no label).

Checks run **from the probe machine** against the IP reported by NGT (CP22). If the VM has no IP or the probe is not on the isolated subnet, they are `SKIP`.

### `Tcp`

Port open (TCP connect).

```json
{ "Type": "Tcp", "Port": 445, "Label": "SMB" }
```

### `Http`

HTTP(S) GET, status code compared to `ExpectedStatus`. `{ip}` in the URL is replaced by the VM address. Certificates are not validated. 15 s timeout.

```json
{ "Type": "Http", "Url": "https://{ip}/health", "ExpectedStatus": 200, "Label": "Health endpoint" }
```

| Field | Required | Default |
|---|---|---|
| `Url` | yes | — |
| `ExpectedStatus` | no | `200` |

### `Ldap`

TCP connect then **anonymous RootDSE bind** on the given port — proves that the directory service (Active Directory) is up without needing credentials.

```json
{ "Type": "Ldap", "Port": 389, "Label": "LDAP" }
```

### `Dns`

Resolve `Name` **using the restored VM as DNS server** (`Resolve-DnsName -Server <ip>`). Proves the DNS service answers with its zone data.

```json
{ "Type": "Dns", "Name": "example.local", "Label": "DNS zone" }
```

### `Sql`

Run `Query` with `Invoke-Sqlcmd` against `<ip>,<Port>` (integrated authentication of the account running the script, `TrustServerCertificate`, 15 s timeout). Requires the `SqlServer` module, otherwise `SKIP`. Passes if the query returns a result.

```json
{ "Type": "Sql", "Port": 1433, "Query": "SELECT COUNT(*) FROM sys.databases WHERE state_desc='ONLINE'", "Label": "Online databases" }
```

> Because the restored VM is a clone in an isolated network, domain-integrated authentication may not work (no domain controller reachable, unless one is restored in the same run). Prefer checks that need no credentials (`Tcp`, `Http`, `Ldap` anonymous, `Dns`) for unattended runs.

### Adding a check type

Add a `case` to `Test-AppCheck` in the script, returning `@{ Ok = $true | $false | $null; Detail = '…' }` (`$null` → `SKIP`).

## Report language

`-Language en|fr` (or system culture) selects console strings, HTML report labels and the `Language` field in the JSON report. CSV column headers are technical and identical in both languages (`RunId;Time;CP;VM;Label;Status;Value;Detail`).
