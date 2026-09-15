# Guide utilisateur

[← Installation](installation.md) · [Configuration →](configuration.md) · 🇬🇧 [English version](../en/user-guide.md)

## Déroulement d'une exécution

```
Étape 0  PRÉ-VOL        Authentification VBR, appliance AHV, Prism Central.
                        Contrôle cluster / conteneur / sous-réseau, isolement du
                        sous-réseau, absence de VM étrangère et de VM résiduelle. → CP00–CP04
Étape 1  RESTAURATION   Par VM : dernier point de restauration, contrôle RPO,
                        restauration complète vers "<préfixe><vm>" avec toutes les
                        cartes réseau remappées sur le sous-réseau isolé, démarrage. → CP10–CP12
Étape 2  VÉRIFICATION   Attente de la session (RTO), état de la VM dans Prism, garde-fou
                        réseau, attente de l'IP (NGT), ping, contrôles applicatifs. → CP13–CP30
Étape 3  NETTOYAGE      Arrêt et suppression de la VM de test (-Cleanup).        → CP40
Étape 4  RAPPORT        HTML + CSV + JSON + journal, code de sortie.
```

Les restaurations sont lancées pour toutes les VM d'abord (étape 1), puis vérifiées une par une (étape 2) : plusieurs restaurations tournent donc en parallèle sur l'appliance.

## Ligne de commande

```powershell
.\Test-AhvBackupRestore.ps1 [-VmNames] <string[]>
    [-ConfigPath <string>] [-Language en|fr]
    [-PingCheck] [-Cleanup] [-FailOnWarning] [-ReportDir <string>]
    [-VbrCredential <PSCredential>] [-AhvCredential <PSCredential>] [-PrismCredential <PSCredential>]
    [<surcharges de configuration>] [-WhatIf] [-Verbose]

.\Test-AhvBackupRestore.ps1 -InitConfig [-ConfigPath <string>]
```

### Paramètres principaux

| Paramètre | Description | Défaut |
|---|---|---|
| `-VmNames` | Un ou plusieurs **noms de VM sources, exactement tels qu'affichés dans Veeam**. Position 0 : le nom du paramètre peut être omis. | — (obligatoire) |
| `-ConfigPath` | Fichier de configuration JSON. Les paramètres de ligne de commande ont priorité sur le fichier. | `.\RecoveryVerification.json` |
| `-InitConfig` | Écrit un modèle de configuration dans `-ConfigPath` puis s'arrête. Demande confirmation avant écrasement. | — |
| `-Language` | `en` ou `fr` pour la console et les rapports. | Culture système : `fr-*` → `fr`, sinon `en` |
| `-PingCheck` | Active **CP23** (ping de la VM restaurée depuis cette machine). Nécessite que la sonde soit sur le sous-réseau isolé. | désactivé |
| `-Cleanup` | **Supprime les VM de test** à la fin, ainsi que toute VM `RV-*` résiduelle d'une exécution précédente lors du pré-vol. Sans cette option, les VM sont conservées pour analyse et CP40 est `SKIP`. | désactivé |
| `-FailOnWarning` | Compte les points de contrôle `WARN` comme des échecs pour le code de sortie et le résultat par VM. | désactivé |
| `-ReportDir` | Dossier de sortie HTML / CSV / JSON / journal. Créé s'il n'existe pas. | `.\Reports` |
| `-WhatIf` | Affiche les actions de restauration et de suppression sans les exécuter. Le pré-vol s'exécute quand même. | — |

### Surcharges de configuration

Toute valeur du fichier JSON (sauf `AppChecks`) peut être surchargée pour une exécution : `-VbrServer`, `-VbrPort`, `-AhvAppliance`, `-AhvApiVersion`, `-PrismCentral`, `-PrismPort`, `-TargetClusterName`, `-IsolatedNetworkName`, `-StorageContainerName`, `-VmNamePrefix`, `-MaxRestorePointAgeHours`, `-MaxRestoreMinutes`, `-BootTimeoutMinutes`. Voir [Configuration](configuration.md).

## Scénarios types

### Première exécution — valider la mise en place

```powershell
.\Test-AhvBackupRestore.ps1 -VmNames SRV-FILE01 -WhatIf -Verbose
```

S'authentifie sur les trois systèmes et exécute CP00–CP04. Rien n'est restauré. Corriger tout `KO` avant d'aller plus loin.

### Vérifier deux VM et les conserver pour inspection manuelle

```powershell
.\Test-AhvBackupRestore.ps1 -VmNames SRV-AD01,SRV-FILE01 -PingCheck
```

Les VM de test `RV-SRV-AD01` et `RV-SRV-FILE01` restent allumées dans le sous-réseau isolé. S'y connecter via la console Prism. **La prochaine exécution doit utiliser `-Cleanup`** ou les supprimer manuellement, sinon CP04 bloque.

### Vérification complète automatisée

```powershell
.\Test-AhvBackupRestore.ps1 -VmNames SRV-AD01,SRV-FILE01,SRV-SQL01 -PingCheck -Cleanup -FailOnWarning
if ($LASTEXITCODE -ne 0) { <# alerte #> }
```

### Rotation quotidienne sur tout le parc

```powershell
$all    = Get-Content .\vms.txt              # un nom de VM par ligne
$d      = (Get-Date).DayOfYear
$sample = 0..2 | ForEach-Object { $all[($d * 3 + $_) % $all.Count] }
.\Test-AhvBackupRestore.ps1 -VmNames $sample -Cleanup
```

Trois VM différentes par jour ; la liste complète est couverte en `ceil(N/3)` jours.

### Tâche planifiée (Windows)

```powershell
$action  = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-NoProfile -File C:\Tools\RecoveryVerification\Run.ps1'
$trigger = New-ScheduledTaskTrigger -Daily -At 06:00
Register-ScheduledTask -TaskName 'Veeam Recovery Verification AHV' -Action $action -Trigger $trigger -User 'DOMAINE\svc-rv' -Password '***'
```

Où `Run.ps1` récupère les identifiants depuis un coffre (voir [Installation §4](installation.md#4-comptes)) et appelle le script avec `-Cleanup`.

## Lire les résultats

### Console

Chaque point de contrôle affiche une ligne :

```
  [CP11] OK   SRV-AD01         Âge du point de restauration <= 30 h - 9.4 h
  [CP13] WARN SRV-AD01         Durée de restauration <= 45 min - 51.2 min - RTO cible dépassé
  [CP30] KO   SRV-WEB01        Applicatif : Health - HTTP 503 https://10.99.0.12/health
  [CP23] SKIP SRV-FILE01       Ping depuis la sonde - option -PingCheck non activée
```

Couleurs : vert `OK`, rouge `KO`, jaune `WARN`, gris `SKIP`. Un tableau de synthèse par VM est affiché à la fin, suivi des chemins des quatre fichiers produits.

### Fichiers dans `-ReportDir`

| Fichier | Contenu |
|---|---|
| `RecoveryVerification-<RunId>.html` | Bandeau (SUCCÈS / SUCCÈS AVEC AVERTISSEMENTS / ÉCHEC), indicateurs, synthèse par VM, tableau complet des points de contrôle. Autonome, à partager tel quel. |
| `RecoveryVerification-<RunId>.csv` | Une ligne par point de contrôle, séparateur `;`, UTF-8. Pour Excel / Power BI. |
| `RecoveryVerification-<RunId>.json` | RunId, date, langue, cible, seuils, synthèse, points de contrôle. Pour ingestion SIEM / supervision. |
| `RecoveryVerification-<RunId>.log` | Transcription PowerShell complète (`-Verbose` pour les URL d'API). |

`RunId` est au format `yyyyMMdd-HHmmss`.

### Codes de sortie

| Code | Signification |
|---|---|
| `0` | Tous les points de contrôle OK (ou seulement des WARN sans `-FailOnWarning`). |
| `1` | Au moins un point de contrôle `KO` (ou `WARN` avec `-FailOnWarning`). |
| `2` | Erreur bloquante en pré-vol (authentification, objet manquant, sous-réseau routé, VM résiduelles sans `-Cleanup`) ou erreur fatale inattendue. Les rapports sont quand même produits. |

## Garde-fous de sécurité

- **CP02 (bloquant)** — le sous-réseau cible ne doit pas être externe et ne doit pas avoir de passerelle. Sinon, rien n'est restauré.
- **CP03** — toute VM du sous-réseau isolé qui ne commence pas par le préfixe de test est signalée (quelqu'un d'autre utilise le réseau de test).
- **CP04 (bloquant)** — les VM de test résiduelles d'une exécution précédente sont supprimées avec `-Cleanup`, sinon l'exécution s'arrête.
- **CP21 (garde-fou)** — si une VM restaurée se retrouve avec une carte réseau hors du sous-réseau isolé, elle est **arrêtée immédiatement**.
- **La restauration ne cible jamais la VM d'origine** (`restoreToOriginal = false`), la VM de test porte un nom distinct (`<préfixe><vm>`) et les catégories ne sont pas restaurées.
- Chaque appel d'API bénéficie de 3 tentatives sur erreur réseau / 5xx / 429 et produit un message lisible avec code HTTP et indice (401 identifiants, 403 droits, 404 objet / version d'API).

## Dépannage

| Symptôme | Cause probable / correction |
|---|---|
| CP00 KO `HTTP 401` | Identifiants incorrects, ou en-tête de version d'API VBR refusé → ajuster `Veeam.VbrApiVersion`. |
| CP01 KO `sous-réseau '…' introuvable` | Réseau créé dans Prism mais inventaire de l'appliance non rafraîchi → relancer un rescan du cluster dans l'appliance Veeam AHV. |
| CP02 KO `is_external=True` ou `passerelle=…` | Le sous-réseau est routé. Le recréer en simple VLAN non routé sans passerelle. |
| CP04 KO `VM résiduelle(s)` | Exécution précédente sans `-Cleanup`. Relancer avec `-Cleanup` ou supprimer les VM `RV-*` dans Prism. |
| CP10 KO `aucun point de restauration Nutanix AHV` | Le nom doit correspondre exactement à Veeam (insensible à la casse, sans caractère générique). Vérifier que la VM est dans un job de sauvegarde AHV avec au moins un point de restauration. |
| CP12 KO `statut = Failed` | Ouvrir la session dans la console Veeam ; causes fréquentes : conteneur plein, conflit de nom, appliance déconnectée du cluster. |
| CP22 WARN `aucune IP` | Nutanix Guest Tools non installés / non démarrés dans l'invité, ou OS encore en démarrage → augmenter `BootTimeoutMinutes`. |
| CP23 / CP30 SKIP | `-PingCheck` non activé, ou pas d'IP, ou aucune entrée `AppChecks` pour cette VM. La sonde doit être sur le sous-réseau isolé. |
| CP30 SKIP `SqlServer module missing` | `Install-Module SqlServer`. |
| CP40 KO `supprimer manuellement '…'` | Prism a refusé la suppression (droits, ou VM encore en cours d'arrêt). La supprimer dans Prism. |
| `HTTP 404` sur les appels appliance | Mauvais `Veeam.AhvApiVersion` (`v8` vs `v9`). |

Les lignes marquées `# [API]` dans le script sont celles qui risquent le plus de nécessiter un ajustement si une mise à jour Veeam ou Nutanix modifie le nom d'un champ de réponse.
