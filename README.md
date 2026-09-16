# Recovery Verification for Nutanix AHV — Veeam Backup & Replication

[🇬🇧 English](#english) · [🇫🇷 Français](#français)

![Python 3.9+](https://img.shields.io/badge/Python-3.9%2B%20stdlib%20only-3776AB?logo=python&logoColor=white)
![License MIT](https://img.shields.io/badge/License-MIT-green)
![Platform Nutanix AHV](https://img.shields.io/badge/Platform-Nutanix%20AHV-024DA1)
![Veeam 13.x / 12.x](https://img.shields.io/badge/Veeam-13.x%20%7C%2012.x-00B336)

---

## English

**SureBackup / Virtual Lab is not available for Nutanix AHV.** This Python tool reproduces the same verification logic — restore, boot, application tests, cleanup, report — through the public REST APIs of Veeam Backup & Replication, the Veeam Plug-in for Nutanix AHV and Nutanix Prism Central.

Each run restores a sample of VMs from their latest restore points into an **isolated, non-routed AHV subnet**, checks that they boot and that their services answer, deletes the test VMs, and produces an **HTML / CSV / JSON report**. Console output and reports are available in English or French.

### What it proves

| Question | Checkpoint |
|---|---|
| Are the backups recent enough? | CP10, CP11 — restore point found, age ≤ RPO target |
| Can they be restored, and fast enough? | CP12, CP13 — restore session succeeds, duration ≤ RTO target |
| Do the restored VMs boot and get on the network? | CP20, CP22, CP23 — powered on, IP reported by Nutanix Guest Tools, ping |
| Do the applications answer? | CP30 — TCP / HTTP / LDAP / DNS / SQL checks per VM |
| Is production safe? | CP02, CP03, CP21 — subnet isolation enforced before, during and after |
| Is the environment left clean? | CP04, CP40 — no leftovers, test VMs deleted |

### Quick start

```bash
# any Linux or Windows probe with Python 3.9+ (standard library only)
./ahv_backup_restore.py --init-config                          # 1. template → edit RecoveryVerification.json
./ahv_backup_restore.py -v SRV-AD01 -v SRV-FILE01 --secrets-file ~/.veeam-rv-secrets.json --dry-run    # 2. pre-flight only
./ahv_backup_restore.py -v SRV-AD01 -v SRV-FILE01 --ping-check --cleanup --secrets-file ~/.veeam-rv-secrets.json -l en   # 3. real run
# 4. open the HTML report in ./Reports/ ; schedule with deploy/ (systemd timer or Windows scheduled task)
```

Exit code: `0` all checkpoints OK · `1` at least one checkpoint failed · `2` blocking pre-flight error. Secrets come from `--secrets-file` (chmod 600), environment variables or an interactive prompt — never from the JSON.

### Veeam version support

| Veeam | Mode | Configuration |
|---|---|---|
| **VBR 13.x / 13.1** — AHV plug-in integrated into VBR, **worker** architecture, no standalone appliance | Default | `AhvIntegrated: true`, `AhvApiVersion: "v9"`, `VbrApiVersion: "1.3-rev2"`. `VBR_*` + `PRISM_*` secrets only. |
| **VBR 12.x** — standalone Veeam Plug-in for Nutanix AHV appliance | Legacy | `AhvIntegrated: false`, `AhvAppliance`, `AhvApiVersion: "v8"`, `VbrApiVersion: "1.2-rev0"`. `AHV_USER` / `AHV_PASSWORD` for the appliance. |

In 13.x the plug-in REST API is served by the VBR server (`/extension/…/api/v9`) with the VBR OAuth token; the restore endpoints are unchanged. Details in [Installation](docs/en/installation.md#veeam-13x-integrated-plug-in-vs-12x-appliance).

### Documentation

- [Installation & prerequisites](docs/en/installation.md)
- [User guide](docs/en/user-guide.md)
- [Configuration reference](docs/en/configuration.md)
- [Checkpoints reference](docs/en/checkpoints.md)

### Repository content

| File | Purpose |
|---|---|
| `ahv_backup_restore.py` | The tool — one Python 3 file, standard library only |
| `RecoveryVerification.sample.json` | Sample configuration to copy as `RecoveryVerification.json` |
| `requirements.txt` | Optional modules for Ldap / Dns / Sql checks (`ldap3`, `dnspython`, `pymssql`) |
| `deploy/` | systemd service + timer, daily rotation helper, Windows scheduled task |
| `docs/en/`, `docs/fr/` | Documentation in English and French |
| `legacy/` | v1 PowerShell implementation, kept for reference, not maintained |

### Disclaimer

Illustrative example, provided **without warranty**. Validate in a test environment first. API response field names may vary between Veeam / Nutanix versions; affected lines are tagged `# [API]`. This is not an official Veeam product. Sister project for Proxmox VE: [veeam-proxmox-recovery-verification](https://github.com/CLahiani/veeam-proxmox-recovery-verification).

---

## Français

**SureBackup / Virtual Lab n'est pas disponible pour Nutanix AHV.** Cet outil Python reproduit la même logique de vérification — restauration, démarrage, tests applicatifs, nettoyage, rapport — au travers des API REST publiques de Veeam Backup & Replication, du Veeam Plug-in for Nutanix AHV et de Nutanix Prism Central.

Chaque exécution restaure un échantillon de VM depuis leurs derniers points de restauration vers un **sous-réseau AHV isolé et non routé**, vérifie qu'elles démarrent et que leurs services répondent, supprime les VM de test, puis produit un **rapport HTML / CSV / JSON**. Console et rapports disponibles en français ou en anglais.

### Ce que le script démontre

| Question | Point de contrôle |
|---|---|
| Les sauvegardes sont-elles assez récentes ? | CP10, CP11 — point de restauration trouvé, âge ≤ RPO cible |
| Sont-elles restaurables, et assez vite ? | CP12, CP13 — session de restauration réussie, durée ≤ RTO cible |
| Les VM restaurées démarrent-elles et obtiennent-elles une IP ? | CP20, CP22, CP23 — démarrée, IP remontée par les Nutanix Guest Tools, ping |
| Les applications répondent-elles ? | CP30 — contrôles TCP / HTTP / LDAP / DNS / SQL par VM |
| La production est-elle protégée ? | CP02, CP03, CP21 — isolement du sous-réseau vérifié avant, pendant et après |
| L'environnement est-il laissé propre ? | CP04, CP40 — aucun résidu, VM de test supprimées |

### Démarrage rapide

```bash
# toute sonde Linux ou Windows avec Python 3.9+ (bibliothèque standard uniquement)
./ahv_backup_restore.py --init-config                          # 1. modèle → renseigner RecoveryVerification.json
./ahv_backup_restore.py -v SRV-AD01 -v SRV-FILE01 --secrets-file ~/.veeam-rv-secrets.json --dry-run    # 2. pré-vol seul
./ahv_backup_restore.py -v SRV-AD01 -v SRV-FILE01 --ping-check --cleanup --secrets-file ~/.veeam-rv-secrets.json -l fr   # 3. exécution réelle
# 4. ouvrir le rapport HTML dans ./Reports/ ; planifier avec deploy/ (timer systemd ou tâche planifiée Windows)
```

Code de sortie : `0` tous les points de contrôle OK · `1` au moins un point de contrôle en échec · `2` erreur bloquante en pré-vol. Les secrets viennent de `--secrets-file` (chmod 600), des variables d'environnement ou d'une saisie — jamais du JSON.

### Versions Veeam prises en charge

| Veeam | Mode | Configuration |
|---|---|---|
| **VBR 13.x / 13.1** — plug-in AHV intégré à VBR, architecture à **workers**, plus d'appliance autonome | Défaut | `AhvIntegrated: true`, `AhvApiVersion: "v9"`, `VbrApiVersion: "1.3-rev2"`. Secrets `VBR_*` + `PRISM_*` uniquement. |
| **VBR 12.x** — appliance autonome Veeam Plug-in for Nutanix AHV | Ancien | `AhvIntegrated: false`, `AhvAppliance`, `AhvApiVersion: "v8"`, `VbrApiVersion: "1.2-rev0"`. `AHV_USER` / `AHV_PASSWORD` pour l'appliance. |

En 13.x, l'API REST du plug-in est servie par le serveur VBR (`/extension/…/api/v9`) avec le jeton OAuth de VBR ; les endpoints de restauration sont inchangés. Détails dans [Installation](docs/fr/installation.md#veeam-13x-plug-in-intégré-vs-12x-appliance).

### Documentation

- [Installation et prérequis](docs/fr/installation.md)
- [Guide utilisateur](docs/fr/guide-utilisateur.md)
- [Référence de configuration](docs/fr/configuration.md)
- [Référence des points de contrôle](docs/fr/points-de-controle.md)

### Contenu du dépôt

| Fichier | Rôle |
|---|---|
| `ahv_backup_restore.py` | L'outil — un fichier Python 3, bibliothèque standard uniquement |
| `RecoveryVerification.sample.json` | Configuration exemple à copier en `RecoveryVerification.json` |
| `requirements.txt` | Modules optionnels pour les contrôles Ldap / Dns / Sql (`ldap3`, `dnspython`, `pymssql`) |
| `deploy/` | Service + timer systemd, script de rotation quotidienne, tâche planifiée Windows |
| `docs/en/`, `docs/fr/` | Documentation en anglais et en français |
| `legacy/` | Implémentation PowerShell v1, conservée pour référence, non maintenue |

### Avertissement

Exemple illustratif, fourni **sans garantie**. À valider en environnement de recette avant toute utilisation. Les noms de champs des réponses d'API peuvent varier selon les versions Veeam / Nutanix ; les lignes concernées sont marquées `# [API]`. Ceci n'est pas un produit officiel Veeam. Projet frère pour Proxmox VE : [veeam-proxmox-recovery-verification](https://github.com/CLahiani/veeam-proxmox-recovery-verification).

---

## References / Références

- [Veeam Backup & Replication REST API](https://helpcenter.veeam.com/references/vbr)
- [Veeam Plug-in for Nutanix AHV REST API](https://helpcenter.veeam.com/references/vbahv)
- [Nutanix Prism Central v3 API](https://www.nutanix.dev)

## License / Licence

[MIT](LICENSE)
