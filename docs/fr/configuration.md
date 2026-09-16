# Référence de configuration

[← Guide utilisateur](guide-utilisateur.md) · [Points de contrôle →](points-de-controle.md) · 🇬🇧 [English version](../en/configuration.md)

La configuration est un fichier JSON, `.\RecoveryVerification.json` par défaut (`-ConfigPath` pour changer). Générer un modèle avec `-InitConfig` ou copier `RecoveryVerification.sample.json`.

**Priorité :** valeurs par défaut du script ← fichier JSON ← paramètres de ligne de commande. Toutes les clés sont facultatives ; les clés absentes reprennent les valeurs par défaut. La section `AppChecks`, lorsqu'elle est présente dans le fichier, **remplace** entièrement celle par défaut.

> Garder `RecoveryVerification.json` hors du dépôt Git (il est dans `.gitignore`) : il contient vos noms de serveurs. Ne versionner que le `.sample.json`.

## Exemple complet

```json
{
  "Veeam": {
    "VbrServer": "vbr.example.local",
    "VbrPort": 9419,
    "VbrApiVersion": "1.3-rev2",
    "AhvIntegrated": true,
    "AhvAppliance": "veeam-ahv.example.local",
    "AhvApiVersion": "v9"
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
                   { "Type": "Dns",  "Name": "example.local", "Label": "Zone DNS" },
                   { "Type": "Tcp",  "Port": 88, "Label": "Kerberos" } ],
    "SRV-FILE01": [ { "Type": "Tcp", "Port": 445, "Label": "SMB" } ],
    "SRV-WEB01": [ { "Type": "Http", "Url": "https://{ip}/health", "ExpectedStatus": 200, "Label": "Health endpoint" } ],
    "SRV-SQL01": [ { "Type": "Sql", "Port": 1433, "Query": "SELECT COUNT(*) FROM sys.databases WHERE state_desc='ONLINE'", "Label": "Bases ONLINE" } ]
  }
}
```

## `Veeam`

| Clé | Surcharge CLI | Description | Défaut |
|---|---|---|---|
| `VbrServer` | `-VbrServer` | Serveur Veeam Backup & Replication (FQDN ou IP). | `vbr.example.local` |
| `VbrPort` | `-VbrPort` | Port de l'API REST VBR. | `9419` |
| `VbrApiVersion` | `-VbrApiVersion` | Valeur de l'en-tête `x-api-version`. **`1.3-rev2` pour VBR 13.1 (`1.3-rev1` pour 13.0)**, `1.2-rev0` pour 12.x. | `1.3-rev2` |
| `AhvIntegrated` | `-AhvIntegrated` | **`true` = VBR 13.x** (plug-in intégré à VBR, architecture à workers, API du plug-in servie par le serveur VBR avec le jeton VBR). **`false` = appliance autonome VBR 12.x**. Voir [Installation](installation.md#veeam-13x-plug-in-intégré-vs-12x-appliance). | `true` |
| `AhvAppliance` | `-AhvAppliance` | **12.x uniquement** (`AhvIntegrated: false`) : FQDN ou IP de l'appliance (HTTPS 443). Ignoré en 13.x. | `veeam-ahv.example.local` |
| `AhvApiVersion` | `-AhvApiVersion` | Version de l'API REST du plug-in : **`v9` pour 13.x**, `v8` pour l'appliance 12.x. | `v9` |

## `Nutanix`

| Clé | Surcharge CLI | Description | Défaut |
|---|---|---|---|
| `PrismCentral` | `-PrismCentral` | Prism Central (FQDN ou IP). | `prism.example.local` |
| `PrismPort` | `-PrismPort` | Port de l'API Prism. | `9440` |

## `Target`

| Clé | Surcharge CLI | Description | Défaut |
|---|---|---|---|
| `ClusterName` | `-TargetClusterName` | Cluster AHV recevant les restaurations de test, **tel que nommé dans l'appliance Veeam**. | `CLUSTER-01` |
| `IsolatedNetworkName` | `-IsolatedNetworkName` | Nom du sous-réseau isolé, identique dans Prism et dans l'inventaire de l'appliance. Vérifié par CP01 et CP02. | `VLAN-RecoveryVerification` |
| `StorageContainerName` | `-StorageContainerName` | Conteneur de stockage pour les disques restaurés. Le dimensionner pour votre plus gros échantillon. | `default-container` |
| `VmNamePrefix` | `-VmNamePrefix` | Préfixe des VM de test (`<préfixe><nom source>`). Sert aussi à CP03 / CP04 pour reconnaître les VM de test — **ne jamais** utiliser un préfixe correspondant à des VM de production. | `RV-` |

## `Thresholds`

| Clé | Surcharge CLI | Description | Défaut |
|---|---|---|---|
| `MaxRestorePointAgeHours` | `-MaxRestorePointAgeHours` | **RPO cible.** CP11 est `KO` si le dernier point de restauration est plus ancien. Régler sur l'intervalle de sauvegarde plus une marge (job quotidien → 30 h). | `30` |
| `MaxRestoreMinutes` | `-MaxRestoreMinutes` | **RTO cible.** CP13 est `WARN` si la session de restauration dure plus longtemps. En 13.x, inclure le temps de démarrage du worker (quelques minutes s'il est éteint). | `45` |
| `BootTimeoutMinutes` | `-BootTimeoutMinutes` | Attente maximale pour que la VM soit `ON` et remonte une IP via NGT (CP20–CP22). S'ajoute aussi à `MaxRestoreMinutes` comme délai maximal de la session de restauration. | `15` |
| `PollIntervalSeconds` | — | Intervalle d'interrogation de l'état des sessions et des VM. | `20` |

## `AppChecks`

Une table **nom de VM → liste de contrôles**. La clé spéciale `"*"` s'applique à toutes les VM et se cumule avec la liste propre à la VM. Chaque contrôle produit un point de contrôle **CP30** libellé `Applicatif : <Label>` (ou `<Type>` sans libellé).

Les contrôles s'exécutent **depuis la machine sonde** vers l'IP remontée par NGT (CP22). Si la VM n'a pas d'IP ou si la sonde n'est pas sur le sous-réseau isolé, ils sont `SKIP`.

### `Tcp`

Port ouvert (connexion TCP).

```json
{ "Type": "Tcp", "Port": 445, "Label": "SMB" }
```

### `Http`

GET HTTP(S), code de statut comparé à `ExpectedStatus`. `{ip}` dans l'URL est remplacé par l'adresse de la VM. Les certificats ne sont pas validés. Délai de 15 s.

```json
{ "Type": "Http", "Url": "https://{ip}/health", "ExpectedStatus": 200, "Label": "Health endpoint" }
```

| Champ | Obligatoire | Défaut |
|---|---|---|
| `Url` | oui | — |
| `ExpectedStatus` | non | `200` |

### `Ldap`

Connexion TCP puis **bind anonyme RootDSE** sur le port indiqué — prouve que le service d'annuaire (Active Directory) est opérationnel sans nécessiter d'identifiants.

```json
{ "Type": "Ldap", "Port": 389, "Label": "LDAP" }
```

### `Dns`

Résout `Name` **en utilisant la VM restaurée comme serveur DNS** (`Resolve-DnsName -Server <ip>`). Prouve que le service DNS répond avec les données de sa zone.

```json
{ "Type": "Dns", "Name": "example.local", "Label": "Zone DNS" }
```

### `Sql`

Exécute `Query` avec `Invoke-Sqlcmd` sur `<ip>,<Port>` (authentification intégrée du compte exécutant le script, `TrustServerCertificate`, délai 15 s). Nécessite le module `SqlServer`, sinon `SKIP`. Réussit si la requête renvoie un résultat.

```json
{ "Type": "Sql", "Port": 1433, "Query": "SELECT COUNT(*) FROM sys.databases WHERE state_desc='ONLINE'", "Label": "Bases ONLINE" }
```

> La VM restaurée étant un clone dans un réseau isolé, l'authentification intégrée au domaine peut ne pas fonctionner (aucun contrôleur de domaine joignable, sauf si l'un d'eux est restauré dans la même exécution). Privilégier les contrôles sans identifiants (`Tcp`, `Http`, `Ldap` anonyme, `Dns`) pour les exécutions non supervisées.

### Ajouter un type de contrôle

Ajouter un `case` dans `Test-AppCheck` du script, renvoyant `@{ Ok = $true | $false | $null; Detail = '…' }` (`$null` → `SKIP`).

## Langue des rapports

`-Language en|fr` (ou culture système) sélectionne les chaînes de la console, les libellés du rapport HTML et le champ `Language` du rapport JSON. Les en-têtes de colonnes CSV sont techniques et identiques dans les deux langues (`RunId;Time;CP;VM;Label;Status;Value;Detail`).
