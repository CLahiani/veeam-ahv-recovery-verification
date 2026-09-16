# Installation et prérequis

[← README](../../README.md) · [Guide utilisateur →](guide-utilisateur.md) · 🇬🇧 [English version](../en/installation.md)

## 1. Logiciels

| Composant | Exigence |
|---|---|
| Machine sonde | Tout hôte **Linux ou Windows** avec **Python 3.9+**. Bibliothèque standard uniquement pour le cœur ; `dnspython` / `ldap3` / `pymssql` optionnels pour les contrôles Ldap / Dns / Sql (`pip install -r requirements.txt`). Une petite VM Linux est le choix naturel. |
| Veeam Backup & Replication | API REST activée (port **9419** par défaut). `Veeam.VbrApiVersion` = `1.3-rev2` pour VBR 13.1 (`1.3-rev1` pour 13.0), `1.2-rev0` pour 12.x. |
| Veeam Plug-in for Nutanix AHV | Voir [Veeam 13.x vs 12.x](#veeam-13x-plug-in-intégré-vs-12x-appliance) ci-dessous. |
| Nutanix Prism Central | API v3 (port **9440** par défaut). |
| VM sources | **Nutanix Guest Tools** installés — l'IP est relue depuis NGT (CP22) ; CP23 / CP30 en dépendent. |

## Veeam 13.x (plug-in intégré) vs 12.x (appliance)

La façon dont l'outil dialogue avec le plug-in AHV dépend de votre version de Veeam. Régler `Veeam.AhvIntegrated` en conséquence (défaut `true`).

| | **VBR 13.x** — `AhvIntegrated: true` | **VBR 12.x** — `AhvIntegrated: false` |
|---|---|---|
| Architecture | Plug-in intégré à VBR ; des **workers** (VM Linux légères déployées sur le cluster AHV par VBR) assurent le transfert. Plus d'appliance autonome. | Appliance autonome Veeam Plug-in for Nutanix AHV (VM proxy). |
| URL de base de l'API REST du plug-in | `https://<serveur VBR>/extension/799a5a3e-ae1e-4eaf-86eb-8a9acc2670e2/api/v9` | `https://<appliance>/api/v8` |
| Authentification | **Jeton OAuth VBR** réutilisé. Pas de troisième identifiant. | Point OAuth propre à l'appliance (`AHV_USER` / `AHV_PASSWORD`). |
| `AhvApiVersion` | `v9` | `v8` |
| `AhvAppliance` | Ignoré | FQDN / IP de l'appliance |
| Versions minimales | VBR **13.0.1.1071+**, plug-in **13.9.0.212+**, AOS **6.8.1.6+**, Prism Central pc.2022.6 – pc.2024.3.1.10 ou **pc.7.3+** (pc.7.3.1.2, 7.3.1.3 et 7.5.0.0 exclus). iSCSI Data Services IP configurée sur le cluster. | Plug-in 6/7/8 selon la matrice de compatibilité Veeam. |

**Workers (13.x).** Au moins un worker AHV doit être configuré dans VBR (*Backup Infrastructure → Backup Proxies → Add → Nutanix AHV worker*), idéalement un par cluster. VBR démarre le worker au lancement d'une session de restauration et l'arrête à la fin : la première restauration d'une exécution peut prendre quelques minutes de plus (démarrage du worker, plus une vérification de mise à jour optionnelle désactivable). En tenir compte dans `Thresholds.MaxRestoreMinutes`. L'outil ne gère pas les workers — c'est VBR.

**Endpoints.** `/clusters`, `/clusters/{id}/networks`, `/clusters/{id}/storageContainers`, `/restorePoints/restore`, `/sessions/{id}` sont identiques en v8 et v9. La découverte des NIC utilise `/restorePoints/{id}/metadata` (v9) avec bascule automatique vers `/networkAdapters` (v8, déprécié). Les points de restauration viennent de `GET /api/v1/restorePoints` (VBR 13) avec bascule vers `/objectRestorePoints` (VBR 12).

## 2. Réseau : le sous-réseau isolé

Créer dans Prism un sous-réseau dédié qui est un **VLAN non routé**, **sans passerelle par défaut** dans son IPAM (ou sans IPAM), et **non marqué externe** (`is_external = false`). L'outil vérifie les trois points à chaque exécution (**CP02**, bloquant) et refuse de restaurer sinon.

Activer éventuellement l'IPAM Nutanix (DHCP) pour que les VM restaurées obtiennent une adresse ; sinon elles conservent leur IP statique de production, acceptable dans un VLAN isolé. Dans tous les cas l'IP est relue depuis **NGT**. Après création du sous-réseau, **relancer un rescan du serveur Nutanix dans Veeam** (13.x : *Backup Infrastructure → Managed Servers* ; 12.x : dans l'appliance) pour que CP01 le trouve par son nom.

## 3. La machine sonde

| Destination | Port | Usage |
|---|---|---|
| Serveur VBR | 9419/tcp | Points de restauration, authentification |
| Serveur VBR (13.x) **ou** appliance AHV (12.x) | 443/tcp | Lancer et suivre les restaurations via l'API REST du plug-in |
| Prism Central | 9440/tcp | Inspecter VM / sous-réseaux, arrêter, supprimer |
| Sous-réseau isolé | ICMP, ports applicatifs | Ping CP23 et contrôles applicatifs CP30 |

Pour la dernière ligne la sonde a besoin d'une **seconde NIC attachée au sous-réseau isolé**. Sans cela l'outil fonctionne ; CP23 et CP30 sont `SKIP`.

## 4. Comptes

| Système | Rôle minimal | Clés de secrets |
|---|---|---|
| Veeam Backup & Replication | 13.x : rôle autorisé à **lire les points de restauration et lancer des restaurations de VM Nutanix AHV** (Veeam Restore Operator, ou rôle RBAC personnalisé 13.1). 12.x : Veeam Restore Operator. | `VBR_USER`, `VBR_PASSWORD` |
| Appliance Veeam AHV (**12.x uniquement**) | Portal Administrator ou Restore Operator. | `AHV_USER`, `AHV_PASSWORD` |
| Prism Central | **Cluster Admin** ou rôle personnalisé avec *lecture VM / sous-réseau*, *mise à jour VM* (arrêt), *suppression VM*. | `PRISM_USER`, `PRISM_PASSWORD` |

Les secrets sont lus depuis `--secrets-file` (JSON, `chmod 600`), puis les variables d'environnement, puis la saisie interactive. Jamais dans `RecoveryVerification.json`.

## 5. Installer

```bash
# sonde Linux
sudo mkdir -p /opt/veeam-recovery-verification /var/lib/veeam-recovery-verification/reports
cd /opt/veeam-recovery-verification
# copier ahv_backup_restore.py, RecoveryVerification.sample.json, deploy/ (git clone ou scp)
chmod +x ahv_backup_restore.py deploy/rotate-sample.sh
./ahv_backup_restore.py --init-config              # écrit RecoveryVerification.json - le renseigner
cat > ~/.veeam-rv-secrets.json <<'EOF'
{ "VBR_USER": "svc-rv", "VBR_PASSWORD": "…", "PRISM_USER": "svc-rv", "PRISM_PASSWORD": "…" }
EOF
chmod 600 ~/.veeam-rv-secrets.json
./ahv_backup_restore.py -v SRV-A --secrets-file ~/.veeam-rv-secrets.json --dry-run --debug   # pré-vol seul
```

```powershell
# sonde Windows (Python 3 depuis python.org / winget)
py -3 ahv_backup_restore.py --init-config
py -3 ahv_backup_restore.py -v SRV-A --secrets-file C:\ProgramData\VeeamRV\secrets.json --dry-run
```

## 6. Planification

- **Linux** : `deploy/veeam-recovery-verification-ahv.service` + `.timer` (systemd), ou `deploy/rotate-sample.sh` pour une rotation quotidienne sur `vms.txt`. `SuccessExitStatus=1 2` garde l'unité verte quand une vérification échoue ; le résultat est dans les rapports.
- **Windows** : `deploy/windows-scheduled-task.ps1` enregistre une tâche planifiée quotidienne lançant `python.exe`.

## 7. TLS

Les appels REST ignorent la validation des certificats par défaut (auto-signés VBR / Prism). Ajouter `--verify-tls` une fois des certificats de confiance en place.

## Étape suivante

Lire le [Guide utilisateur](guide-utilisateur.md).
