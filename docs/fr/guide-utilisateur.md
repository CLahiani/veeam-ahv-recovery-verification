# Guide utilisateur

[← Installation](installation.md) · [Configuration →](configuration.md) · 🇬🇧 [English version](../en/user-guide.md)

## Déroulement d'une exécution

```
Étape 0  PRÉ-VOL        Authentification VBR (+ API du plug-in AHV), Prism Central. Cluster / conteneur /
                        sous-réseau présents, sous-réseau isolé, aucune VM étrangère, aucune VM résiduelle. → CP00–CP04
Étape 1  RESTAURATION   Par VM : dernier point de restauration, contrôle RPO, restauration complète vers
                        "<préfixe><vm>" avec toutes les NIC remappées sur le sous-réseau isolé, démarrage. → CP10–CP12
Étape 2  VÉRIFICATION   Attente de la session (RTO), état de la VM dans Prism, garde-fou NIC, IP NGT, ping,
                        contrôles applicatifs depuis la sonde.                                       → CP13–CP30
Étape 3  NETTOYAGE      Arrêt et suppression de la VM de test (--cleanup).                           → CP40
Étape 4  RAPPORT        HTML + CSV + JSON + journal, code de sortie.
```

Les restaurations sont lancées pour toutes les VM d'abord (étape 1), puis vérifiées une par une (étape 2) : plusieurs restaurations tournent en parallèle sur le plug-in.

## Ligne de commande

```
ahv_backup_restore.py -v NOM [-v NOM ...] [-c CONFIG] [-l en|fr] [--cleanup] [--ping-check] [--fail-on-warning]
                      [--report-dir DIR] [--secrets-file FICHIER] [--verify-tls] [-n|--dry-run] [--debug]
                      [surcharges de configuration]
ahv_backup_restore.py --init-config [--force] [-c CONFIG]
```

| Option | Description | Défaut |
|---|---|---|
| `-v`, `--vm NOM` | Nom de la VM source **exactement tel qu'affiché dans Veeam**. Répéter pour plusieurs VM. | obligatoire |
| `-c`, `--config` | Fichier de configuration JSON. | `./RecoveryVerification.json` |
| `--init-config` / `--force` | Écrit le modèle de configuration (écrase avec `--force`) puis s'arrête. | — |
| `-l`, `--language` | `en` ou `fr` pour la console et les rapports. | locale système |
| `--ping-check` | Active CP23 (ping depuis la sonde ; NIC sur le sous-réseau isolé requise). | désactivé |
| `--cleanup` | **Supprime les VM de test** à la fin, et les VM `<préfixe>*` résiduelles en pré-vol. Sans cette option les VM sont conservées et CP40 est `SKIP`. | désactivé |
| `--fail-on-warning` | Compte les `WARN` comme échecs pour le code de sortie. | désactivé |
| `--report-dir` | Dossier de sortie des rapports et du journal. | `./Reports` |
| `--secrets-file` | JSON avec `VBR_USER`, `VBR_PASSWORD`, `PRISM_USER`, `PRISM_PASSWORD` (+ `AHV_USER`, `AHV_PASSWORD` en 12.x). Variables d'environnement puis saisie en secours. | — |
| `--verify-tls` | Valide les certificats. | désactivé |
| `-n`, `--dry-run` | Le pré-vol s'exécute réellement ; restauration / suppression seulement affichées. | — |
| `--debug` | Affiche aussi le journal de debug (appels REST) sur la console. | — |

Surcharges de configuration : `--vbr-server --vbr-port --vbr-api-version --ahv-integrated true|false --ahv-appliance --ahv-api-version --prism-central --prism-port --cluster-name --isolated-network-name --storage-container-name --vm-name-prefix --max-restore-point-age-hours --max-restore-minutes --boot-timeout-minutes`.

## Scénarios types

```bash
# première exécution - valider la mise en place (CP00-CP04), rien n'est restauré ; le détail de CP00 indique le mode (13.x intégré / 12.x appliance)
./ahv_backup_restore.py -v SRV-FILE01 --secrets-file ~/.veeam-rv-secrets.json --dry-run --debug

# ancien mode VBR 12.x avec appliance autonome
./ahv_backup_restore.py -v SRV-A --cleanup --ahv-integrated false --ahv-appliance veeam-ahv.local --ahv-api-version v8 --vbr-api-version 1.2-rev0

# restaurer deux VM et les conserver pour inspection (console Prism) - la prochaine exécution doit utiliser --cleanup, sinon CP04 bloque
./ahv_backup_restore.py -v SRV-AD01 -v SRV-FILE01 --ping-check --secrets-file ~/.veeam-rv-secrets.json

# vérification complète automatisée
./ahv_backup_restore.py -v SRV-AD01 -v SRV-FILE01 -v SRV-SQL01 --ping-check --cleanup --fail-on-warning --secrets-file ~/.veeam-rv-secrets.json
echo $?      # 0 OK, 1 point de contrôle en échec, 2 pré-vol / fatal

# rotation quotidienne de 3 VM depuis vms.txt : deploy/rotate-sample.sh + timer systemd (Linux) ou deploy/windows-scheduled-task.ps1
```

## Lire les résultats

```
  [CP00] OK   -                Authentification VBR / plug-in AHV / Prism Central - plug-in intégré VBR 13.x (v9)
  [CP11] OK   SRV-AD01         Âge du point de restauration <= 30 h - 9.4 h
  [CP13] WARN SRV-AD01         Durée de restauration <= 45 min - 51.2 min - RTO cible dépassé
  [CP30] KO   SRV-WEB01        Applicatif : Health - HTTP 503 https://10.99.0.12/health
```

| Fichier dans `--report-dir` | Contenu |
|---|---|
| `RecoveryVerification-<RunId>.html` | Bandeau, indicateurs, synthèse par VM, tableau des points de contrôle. Autonome. |
| `RecoveryVerification-<RunId>.csv` | Une ligne par point de contrôle, séparateur `;`, UTF-8. |
| `RecoveryVerification-<RunId>.json` | RunId, `Platform: NutanixAHV`, `Method: FullRestoreToIsolatedSubnet`, cible, seuils, synthèse, points de contrôle. |
| `RecoveryVerification-<RunId>.log` | Journal de debug : appels REST, traces. |

Codes de sortie : `0` tout OK · `1` au moins un `KO` (ou `WARN` avec `--fail-on-warning`) · `2` erreur bloquante en pré-vol ou fatale (rapports quand même produits).

## Garde-fous de sécurité

- **CP02 (bloquant)** — le sous-réseau cible ne doit être ni externe ni doté d'une passerelle.
- **CP03** — toute VM hors test sur le sous-réseau isolé est signalée.
- **CP04 (bloquant)** — les VM de test résiduelles sont supprimées avec `--cleanup`, sinon l'exécution s'arrête.
- **CP21 (garde-fou)** — une VM restaurée avec une NIC hors du sous-réseau isolé est **arrêtée immédiatement**.
- La restauration ne cible jamais la VM d'origine (`restoreToOriginal = false`), la VM de test porte un nom distinct, les catégories ne sont pas restaurées.
- Les appels REST réessaient 3× sur erreur réseau / 5xx / 429 et produisent des messages lisibles (401 identifiants, 403 droits, 404 objet / version d'API).

## Dépannage

| Symptôme | Cause probable / correction |
|---|---|
| CP00 KO `HTTP 401` | Identifiants incorrects, ou `VbrApiVersion` refusé (`1.3-rev2` 13.1 / `1.2-rev0` 12.x). |
| CP00 KO `HTTP 404` sur `/extension/…/api/v9/clusters` | Mode 13.x contre un serveur 12.x, ou plug-in AHV non installé sur VBR → vérifier `AhvIntegrated`, installer le plug-in. |
| CP00 KO connexion refusée sur l'appliance | `AhvIntegrated: false` contre un environnement 13.x (appliance disparue) → `AhvIntegrated: true`, `AhvApiVersion: v9`. |
| CP01 KO `sous-réseau '…' introuvable` | Réseau créé dans Prism mais inventaire du plug-in non rafraîchi → rescan du serveur Nutanix dans VBR (13.x) / appliance (12.x). |
| CP02 KO `is_external=True` ou `passerelle=…` | Sous-réseau routé. Le recréer en simple VLAN non routé sans passerelle. |
| CP04 KO `VM résiduelle(s)` | Exécution précédente sans `--cleanup`. Relancer avec `--cleanup` ou supprimer les VM `<préfixe>*` dans Prism. |
| CP10 KO `aucun point de restauration Nutanix AHV` | Nom Veeam exact requis ; la VM doit être dans un job AHV avec un point de restauration. |
| CP12 KO `statut = Failed` | Ouvrir la session dans la console Veeam : conteneur plein, conflit de nom, worker / appliance déconnecté. |
| CP12 KO / CP13 WARN, démarrage lent (13.x) | Worker éteint ou en mise à jour ; aucun worker sur le cluster cible. Ajouter un worker par cluster, désactiver la vérification de mise à jour, augmenter `MaxRestoreMinutes`. |
| CP22 WARN `aucune IP` | NGT non installés / non démarrés, ou OS en démarrage → augmenter `BootTimeoutMinutes`. |
| CP23 / CP30 SKIP | `--ping-check` désactivé, pas d'IP, aucune entrée `AppChecks`, ou sonde hors du sous-réseau isolé. |
| CP30 SKIP `module python … absent` | `pip install dnspython ldap3 pymssql` (ou `-r requirements.txt`). |
| CP40 KO | Prism a refusé la suppression (droits, VM encore en arrêt). La supprimer dans Prism. |
| `HTTP 404` sur les appels du plug-in | Mauvais `AhvApiVersion` (`v9` 13.x / `v8` 12.x). |
