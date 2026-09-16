# Changelog

All notable changes to this project are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Toutes les évolutions notables de ce projet sont consignées ici. Format basé sur [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

## [2.0.1] - 2026-09-16

### Fixed / Corrigé
- **EN** RTO measurement: restore sessions are now polled round-robin (`Ahv.wait_sessions`) so each VM's duration is its own, not inflated by the time spent waiting on earlier VMs. `examples/` added (reports on fake data); `.gitattributes` for GitHub language statistics.
- **FR** Mesure du RTO : les sessions de restauration sont désormais interrogées en tourniquet (`Ahv.wait_sessions`), la durée de chaque VM est la sienne et non gonflée par l'attente des VM précédentes. Ajout de `examples/` (rapports sur données fictives) ; `.gitattributes` pour les statistiques de langage GitHub.

## [2.0.0] - 2026-09-16

### Changed / Modifié
- **EN** Rewritten in **Python 3** (`ahv_backup_restore.py`, standard library only) for any Linux or Windows probe. Same checkpoints CP00–CP40, same HTML / CSV / JSON reports, same exit codes, same dual mode (`Veeam.AhvIntegrated` 13.x / 12.x). Secrets via `--secrets-file` (chmod 600), environment variables (`VBR_*`, `PRISM_*`, `AHV_*`) or prompt — never in the JSON. CLI: `-v/--vm`, `--cleanup`, `--dry-run`, `--ping-check`, `--fail-on-warning`, `-l en|fr`, `--verify-tls`, `--debug`, `--init-config`, `--ahv-integrated true|false`. Ldap / Dns / Sql checks use optional `ldap3` / `dnspython` / `pymssql` (SQL login instead of Windows integrated auth). `deploy/` adds a systemd service + timer, a daily rotation helper and a Windows scheduled-task registration script.
- **FR** Réécriture en **Python 3** (`ahv_backup_restore.py`, bibliothèque standard uniquement) pour toute sonde Linux ou Windows. Mêmes points de contrôle CP00–CP40, mêmes rapports HTML / CSV / JSON, mêmes codes de sortie, même double mode (`Veeam.AhvIntegrated` 13.x / 12.x). Secrets via `--secrets-file` (chmod 600), variables d'environnement (`VBR_*`, `PRISM_*`, `AHV_*`) ou saisie — jamais dans le JSON. CLI : `-v/--vm`, `--cleanup`, `--dry-run`, `--ping-check`, `--fail-on-warning`, `-l en|fr`, `--verify-tls`, `--debug`, `--init-config`, `--ahv-integrated true|false`. Les contrôles Ldap / Dns / Sql utilisent `ldap3` / `dnspython` / `pymssql` optionnels (login SQL au lieu de l'authentification intégrée Windows). `deploy/` ajoute un service + timer systemd, un script de rotation quotidienne et un script d'enregistrement de tâche planifiée Windows.

### Deprecated / Déprécié
- **EN/FR** The PowerShell script moves to `legacy/` and is no longer maintained. / Le script PowerShell passe dans `legacy/` et n'est plus maintenu.

## [1.1.1] - 2026-09-16

### Fixed / Corrigé
- **EN** Restore point lookup uses the VBR 13 REST endpoint `GET /api/v1/restorePoints` (`platformNameFilter=Nutanix`) with automatic fallback to the VBR 12 endpoint `/objectRestorePoints` (`NutanixAhv`). Also sets `VbrApiVersion` default to `1.3-rev2` (13.1).
- **FR** La recherche du point de restauration utilise l'endpoint REST VBR 13 `GET /api/v1/restorePoints` (`platformNameFilter=Nutanix`) avec bascule automatique vers l'endpoint VBR 12 `/objectRestorePoints` (`NutanixAhv`). La valeur par défaut de `VbrApiVersion` passe à `1.3-rev2` (13.1).

## [1.1.0] - 2026-09-15

### Added / Ajouté
- **EN** Support for **VBR 13.x / 13.1** with the AHV plug-in integrated into VBR (worker architecture). New `Veeam.AhvIntegrated` key (default `true`) and `-AhvIntegrated` / `-VbrApiVersion` overrides. In integrated mode the plug-in REST API is reached through the VBR server (`/extension/799a5a3e-ae1e-4eaf-86eb-8a9acc2670e2/api/v9`) with the VBR OAuth token; no appliance credential is prompted. `Connect-AhvIntegrated` and `Get-RestorePointNics` functions.
- **FR** Prise en charge de **VBR 13.x / 13.1** avec le plug-in AHV intégré à VBR (architecture à workers). Nouvelle clé `Veeam.AhvIntegrated` (défaut `true`) et surcharges `-AhvIntegrated` / `-VbrApiVersion`. En mode intégré, l'API REST du plug-in est atteinte via le serveur VBR (`/extension/799a5a3e-ae1e-4eaf-86eb-8a9acc2670e2/api/v9`) avec le jeton OAuth de VBR ; aucun identifiant appliance n'est demandé. Fonctions `Connect-AhvIntegrated` et `Get-RestorePointNics`.

### Changed / Modifié
- **EN** Defaults: `VbrApiVersion` `1.3-rev1`, `AhvApiVersion` `v9`. NIC discovery uses `/restorePoints/{id}/metadata` (v9) with automatic fallback to the deprecated `/networkAdapters` (v8). CP00 detail now shows the mode in use. Docs (EN/FR) updated: 13.x prerequisites, workers, troubleshooting.
- **FR** Valeurs par défaut : `VbrApiVersion` `1.3-rev1`, `AhvApiVersion` `v9`. La découverte des cartes réseau utilise `/restorePoints/{id}/metadata` (v9) avec bascule automatique vers `/networkAdapters` (v8, déprécié). Le détail de CP00 indique désormais le mode utilisé. Docs (EN/FR) mises à jour : prérequis 13.x, workers, dépannage.
- **EN/FR** 12.x standalone appliance remains supported with `AhvIntegrated: false` / reste pris en charge avec `AhvIntegrated: false`.

## [1.0.0] - 2026-09-15

### Added / Ajouté
- **EN** Initial release: scripted Recovery Verification for Nutanix AHV (restore to isolated subnet, boot and application checks, cleanup, HTML/CSV/JSON report). Bilingual console and reports (`-Language en|fr`). JSON configuration with `-InitConfig` template. `-WhatIf` support. Checkpoints CP00–CP40. Exit codes 0/1/2.
- **FR** Version initiale : Recovery Verification scriptée pour Nutanix AHV (restauration vers sous-réseau isolé, contrôles de démarrage et applicatifs, nettoyage, rapport HTML/CSV/JSON). Console et rapports bilingues (`-Language en|fr`). Configuration JSON avec modèle `-InitConfig`. Prise en charge de `-WhatIf`. Points de contrôle CP00–CP40. Codes de sortie 0/1/2.
- **EN/FR** Documentation in English and French (`docs/en`, `docs/fr`).
