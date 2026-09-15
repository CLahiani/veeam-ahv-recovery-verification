# Recovery Verification for Nutanix AHV — Veeam Backup & Replication

[🇬🇧 English](#english) · [🇫🇷 Français](#français)

![PowerShell 7.2+](https://img.shields.io/badge/PowerShell-7.2%2B-5391FE?logo=powershell&logoColor=white)
![License MIT](https://img.shields.io/badge/License-MIT-green)
![Platform Nutanix AHV](https://img.shields.io/badge/Platform-Nutanix%20AHV-024DA1)

---

## English

**SureBackup / Virtual Lab is not available for Nutanix AHV.** This PowerShell script reproduces the same verification logic — restore, boot, application tests, cleanup, report — through the public REST APIs of Veeam Backup & Replication, the Veeam Plug-in for Nutanix AHV and Nutanix Prism Central.

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

```powershell
# 1. Generate the configuration template
.\Test-AhvBackupRestore.ps1 -InitConfig

# 2. Edit RecoveryVerification.json (servers, target cluster / subnet, thresholds, app checks)

# 3. Dry run — shows what would be restored / deleted without doing it
.\Test-AhvBackupRestore.ps1 -VmNames SRV-AD01,SRV-FILE01 -Cleanup -WhatIf

# 4. Real run
.\Test-AhvBackupRestore.ps1 -VmNames SRV-AD01,SRV-FILE01 -PingCheck -Cleanup -Language en

# 5. Open the HTML report in .\Reports\
```

Exit code: `0` all checkpoints OK · `1` at least one checkpoint failed · `2` blocking pre-flight error.

### Documentation

- [Installation & prerequisites](docs/en/installation.md)
- [User guide](docs/en/user-guide.md)
- [Configuration reference](docs/en/configuration.md)
- [Checkpoints reference](docs/en/checkpoints.md)

### Repository content

| File | Purpose |
|---|---|
| `Test-AhvBackupRestore.ps1` | The script (single file, no module dependency except `SqlServer` for SQL checks) |
| `RecoveryVerification.sample.json` | Sample configuration to copy as `RecoveryVerification.json` |
| `docs/en/`, `docs/fr/` | Documentation in English and French |

### Disclaimer

Illustrative example, provided **without warranty**. Validate in a test environment first. API response field names may vary between Veeam / Nutanix versions; affected lines in the script are tagged `# [API]`. This is not an official Veeam product.

---

## Français

**SureBackup / Virtual Lab n'est pas disponible pour Nutanix AHV.** Ce script PowerShell reproduit la même logique de vérification — restauration, démarrage, tests applicatifs, nettoyage, rapport — au travers des API REST publiques de Veeam Backup & Replication, du Veeam Plug-in for Nutanix AHV et de Nutanix Prism Central.

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

```powershell
# 1. Générer le modèle de configuration
.\Test-AhvBackupRestore.ps1 -InitConfig

# 2. Renseigner RecoveryVerification.json (serveurs, cluster / sous-réseau cible, seuils, contrôles applicatifs)

# 3. Simulation — affiche les restaurations / suppressions sans les exécuter
.\Test-AhvBackupRestore.ps1 -VmNames SRV-AD01,SRV-FILE01 -Cleanup -WhatIf

# 4. Exécution réelle
.\Test-AhvBackupRestore.ps1 -VmNames SRV-AD01,SRV-FILE01 -PingCheck -Cleanup -Language fr

# 5. Ouvrir le rapport HTML dans .\Reports\
```

Code de sortie : `0` tous les points de contrôle OK · `1` au moins un point de contrôle en échec · `2` erreur bloquante en pré-vol.

### Documentation

- [Installation et prérequis](docs/fr/installation.md)
- [Guide utilisateur](docs/fr/guide-utilisateur.md)
- [Référence de configuration](docs/fr/configuration.md)
- [Référence des points de contrôle](docs/fr/points-de-controle.md)

### Contenu du dépôt

| Fichier | Rôle |
|---|---|
| `Test-AhvBackupRestore.ps1` | Le script (fichier unique, aucune dépendance sauf `SqlServer` pour les contrôles SQL) |
| `RecoveryVerification.sample.json` | Configuration exemple à copier en `RecoveryVerification.json` |
| `docs/en/`, `docs/fr/` | Documentation en anglais et en français |

### Avertissement

Exemple illustratif, fourni **sans garantie**. À valider en environnement de recette avant toute utilisation. Les noms de champs des réponses d'API peuvent varier selon les versions Veeam / Nutanix ; les lignes concernées dans le script sont marquées `# [API]`. Ceci n'est pas un produit officiel Veeam.

---

## References / Références

- [Veeam Backup & Replication REST API](https://helpcenter.veeam.com/references/vbr)
- [Veeam Plug-in for Nutanix AHV REST API](https://helpcenter.veeam.com/references/vbahv)
- [Nutanix Prism Central v3 API](https://www.nutanix.dev)

## License / Licence

[MIT](LICENSE)
