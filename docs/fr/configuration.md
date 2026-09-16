# Référence de configuration

[← Guide utilisateur](guide-utilisateur.md) · [Points de contrôle →](points-de-controle.md) · 🇬🇧 [English version](../en/configuration.md)

Fichier JSON, `./RecoveryVerification.json` par défaut (`-c`). Générer avec `--init-config` ou copier `RecoveryVerification.sample.json`.

**Priorité :** valeurs par défaut de l'outil ← fichier JSON ← surcharges de ligne de commande. `AppChecks`, présent dans le fichier, **remplace** entièrement la valeur par défaut. Garder le vrai fichier hors de git (`.gitignore`) ; les secrets n'y vont jamais.

## `Veeam`

| Clé | CLI | Description | Défaut |
|---|---|---|---|
| `VbrServer` / `VbrPort` | `--vbr-server` / `--vbr-port` | Serveur VBR et port REST. | `vbr.example.local` / `9419` |
| `VbrApiVersion` | `--vbr-api-version` | `x-api-version` : **`1.3-rev2` = 13.1**, `1.3-rev1` = 13.0, `1.2-rev0` = 12.x. | `1.3-rev2` |
| `AhvIntegrated` | `--ahv-integrated true|false` | **`true` = VBR 13.x** (plug-in intégré, workers, API du plug-in servie par VBR avec le jeton VBR). **`false` = 12.x** appliance autonome. | `true` |
| `AhvAppliance` | `--ahv-appliance` | **12.x uniquement** : FQDN / IP de l'appliance. Ignoré en 13.x. | `veeam-ahv.example.local` |
| `AhvApiVersion` | `--ahv-api-version` | Version de l'API REST du plug-in : **`v9` pour 13.x**, `v8` pour l'appliance 12.x. | `v9` |

## `Nutanix`

| Clé | CLI | Description | Défaut |
|---|---|---|---|
| `PrismCentral` / `PrismPort` | `--prism-central` / `--prism-port` | Prism Central (FQDN / IP) et port API. | `prism.example.local` / `9440` |

## `Target`

| Clé | CLI | Description | Défaut |
|---|---|---|---|
| `ClusterName` | `--cluster-name` | Cluster AHV recevant les restaurations de test, **tel que nommé dans le plug-in Veeam**. | `CLUSTER-01` |
| `IsolatedNetworkName` | `--isolated-network-name` | Nom du sous-réseau isolé, identique dans Prism et dans l'inventaire du plug-in (CP01, CP02). | `VLAN-RecoveryVerification` |
| `StorageContainerName` | `--storage-container-name` | Conteneur des disques restaurés ; le dimensionner pour le plus gros échantillon. | `default-container` |
| `VmNamePrefix` | `--vm-name-prefix` | Noms `<préfixe><source>` ; identifie aussi les résidus (CP03 / CP04). **Jamais** un préfixe correspondant à des VM de production. | `RV-` |

## `Thresholds`

| Clé | CLI | Description | Défaut |
|---|---|---|---|
| `MaxRestorePointAgeHours` | `--max-restore-point-age-hours` | **RPO cible** — CP11 `KO` si plus ancien (job quotidien → 30 h). | `30` |
| `MaxRestoreMinutes` | `--max-restore-minutes` | **RTO cible** — CP13 `WARN` si la session est plus longue. 13.x : inclure le démarrage du worker. | `45` |
| `BootTimeoutMinutes` | `--boot-timeout-minutes` | Attente maximale de `ON` + IP NGT (CP20–CP22) ; s'ajoute aussi à `MaxRestoreMinutes` comme délai dur de la session. | `15` |
| `PollIntervalSeconds` | — | Intervalle d'interrogation. | `20` |

## `AppChecks`

Table **nom de VM → liste de contrôles** ; `"*"` s'applique à toutes les VM et se cumule avec la liste propre. Un **CP30** par contrôle, exécuté **depuis la sonde** vers l'IP NGT (CP22). `SKIP` sans IP ou si la sonde n'est pas sur le sous-réseau isolé.

| Type | Champs | Réussit si | Requiert |
|---|---|---|---|
| `Tcp` | `Port` | connexion TCP OK | — |
| `Http` | `Url` (avec `{ip}`), `ExpectedStatus` (200) | code attendu (TLS non validé, 15 s) | — |
| `Ldap` | `Port` | bind anonyme RootDSE OK — prouve qu'AD est opérationnel sans identifiants | `ldap3` |
| `Dns` | `Name`, `RecordType` (A) | `<ip>` répond à la requête | `dnspython` |
| `Sql` | `Port`, `Query`, `User`, `Password` | la requête renvoie une ligne (login SQL ; l'authentification intégrée n'est pas disponible depuis une sonde hors domaine) | `pymssql` |

```json
"AppChecks": {
  "*":         [ { "Type": "Tcp", "Port": 3389, "Label": "RDP (Windows)" } ],
  "SRV-AD01":  [ { "Type": "Ldap", "Port": 389, "Label": "LDAP" }, { "Type": "Dns", "Name": "example.local", "Label": "Zone DNS" } ],
  "SRV-WEB01": [ { "Type": "Http", "Url": "https://{ip}/health", "ExpectedStatus": 200, "Label": "Health" } ],
  "SRV-SQL01": [ { "Type": "Sql", "Port": 1433, "Query": "SELECT COUNT(*) FROM sys.databases WHERE state_desc='ONLINE'", "User": "rv_check", "Password": "…", "Label": "Bases ONLINE" } ]
}
```

Module optionnel absent → `SKIP` avec le nom du module. Privilégier les contrôles sans identifiants (`Tcp`, `Http`, `Ldap`, `Dns`) pour les exécutions non supervisées ; la VM restaurée est un clone dans un réseau isolé où l'authentification de domaine peut ne pas fonctionner.

## Secrets

Ordre : `--secrets-file` (JSON, `chmod 600`) → environnement (`VBR_USER`, `VBR_PASSWORD`, `PRISM_USER`, `PRISM_PASSWORD`, et `AHV_USER` / `AHV_PASSWORD` si `AhvIntegrated: false`) → saisie interactive.

## Langue des rapports

`-l en|fr` (ou locale système) pilote les chaînes console, les libellés HTML et le champ `Language` du rapport JSON. En-têtes CSV techniques, identiques dans les deux langues.
