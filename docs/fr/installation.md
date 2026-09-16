# Installation et prérequis

[← README](../../README.md) · [Guide utilisateur →](guide-utilisateur.md) · 🇬🇧 [English version](../en/installation.md)

## 1. Logiciels

| Composant | Exigence |
|---|---|
| PowerShell | **7.2 ou supérieur** (`pwsh`). Windows PowerShell 5.1 n'est pas pris en charge (`SkipCertificateCheck`, opérateur ternaire, `ConvertFrom-Json -AsHashtable`). |
| OS de la machine sonde | Windows recommandé. `Test-NetConnection` et `Resolve-DnsName` (utilisés par les contrôles Tcp / Ldap / Dns) sont des cmdlets Windows. Sous Linux, seuls les contrôles Http et Sql fonctionnent. |
| Module `SqlServer` | Uniquement si des contrôles applicatifs `Sql` sont définis : `Install-Module SqlServer -Scope CurrentUser` |
| Veeam Backup & Replication | API REST activée (port **9419** par défaut). `Veeam.VbrApiVersion` = `1.3-rev2` pour VBR 13.1 (`1.3-rev1` pour 13.0), `1.2-rev0` pour 12.x. |
| Veeam Plug-in for Nutanix AHV | Voir [Veeam 13.x vs 12.x](#veeam-13x-plug-in-intégré-vs-12x-appliance) ci-dessous. |
| Nutanix Prism Central | API v3 (port **9440** par défaut). |

## Veeam 13.x (plug-in intégré) vs 12.x (appliance)

La façon dont le script dialogue avec le plug-in AHV dépend de votre version de Veeam. Régler `Veeam.AhvIntegrated` en conséquence (défaut `true`).

| | **VBR 13.x** — `AhvIntegrated: true` | **VBR 12.x** — `AhvIntegrated: false` |
|---|---|---|
| Architecture | Plug-in intégré à VBR ; des **workers** (VM Linux légères déployées sur le cluster AHV par VBR) assurent le transfert de données. Plus d'appliance autonome. | Appliance autonome Veeam Plug-in for Nutanix AHV (VM proxy). |
| URL de base de l'API REST du plug-in | `https://<serveur VBR>/extension/799a5a3e-ae1e-4eaf-86eb-8a9acc2670e2/api/v9` | `https://<appliance>/api/v8` |
| Authentification | **Jeton OAuth VBR** réutilisé (`/api/oauth2/token` sur le port 9419). Pas de troisième identifiant. | Point d'authentification OAuth propre à l'appliance (`-AhvCredential`). |
| `AhvApiVersion` | `v9` | `v8` |
| `AhvAppliance` | Ignoré | FQDN / IP de l'appliance |
| Versions minimales | VBR **13.0.1.1071+**, plug-in **13.9.0.212+**, AOS **6.8.1.6+**, Prism Central pc.2022.6 – pc.2024.3.1.10 ou **pc.7.3+** (pc.7.3.1.2, 7.3.1.3 et 7.5.0.0 exclus). iSCSI Data Services IP configurée sur le cluster. | Plug-in 6/7/8 selon la matrice de compatibilité Veeam. |

**Workers (13.x).** Au moins un worker AHV doit être configuré dans VBR (*Backup Infrastructure → Backup Proxies → Add → Nutanix AHV worker*), idéalement un par cluster. VBR démarre le worker au lancement d'une session de restauration et l'arrête à la fin : la première restauration d'une exécution peut donc prendre quelques minutes de plus (démarrage du worker, plus une vérification de mise à jour optionnelle désactivable dans les propriétés du worker). En tenir compte dans `Thresholds.MaxRestoreMinutes`. Le script ne gère pas les workers — c'est VBR qui s'en charge.

**Endpoints.** Les endpoints du plug-in utilisés par le script (`/clusters`, `/clusters/{id}/networks`, `/clusters/{id}/storageContainers`, `/restorePoints/restore`, `/sessions/{id}`) sont identiques en v8 et v9. Seule la découverte des cartes réseau diffère : v9 utilise `/restorePoints/{id}/metadata` (`/networkAdapters` de v8 est déprécié) ; le script essaie `metadata` d'abord et bascule automatiquement.

## 2. Réseau : le sous-réseau isolé

C'est le fondement de sécurité de tout le processus. Créer dans Prism un sous-réseau dédié qui est :

- un **VLAN non routé** (aucune interface L3 sur le cœur de réseau) ;
- **sans passerelle par défaut** dans sa configuration IPAM (ou sans IPAM du tout) ;
- **non marqué externe** (`is_external = false`).

Le script vérifie ces trois points à chaque exécution (point de contrôle **CP02**, bloquant) et refuse de restaurer quoi que ce soit si le sous-réseau semble routé.

Activer éventuellement l'IPAM Nutanix (DHCP) sur ce sous-réseau pour que les VM restaurées reçoivent une adresse ; sinon elles conservent leur IP statique de production, ce qui est acceptable puisque le VLAN est isolé. Dans les deux cas, l'IP est relue depuis les **Nutanix Guest Tools** (CP22) : NGT doit donc être installé dans les VM sources pour que CP22 / CP23 / CP30 passent.

Après création du sous-réseau, **relancer un rescan du cluster dans l'appliance Veeam AHV** pour que le réseau apparaisse dans son inventaire (le point de contrôle **CP01** le recherche par son nom).

## 3. La machine sonde

Le script doit s'exécuter depuis une machine capable de joindre :

| Destination | Port | Usage |
|---|---|---|
| Serveur VBR | 9419/tcp | Rechercher les derniers points de restauration, s'authentifier |
| Serveur VBR (13.x) **ou** appliance AHV (12.x) | 443/tcp | Lancer et suivre les restaurations via l'API REST du plug-in |
| Prism Central | 9440/tcp | Inspecter VM / sous-réseaux, arrêter, supprimer |
| Sous-réseau isolé | ICMP, ports applicatifs | Ping CP23 et contrôles applicatifs CP30 |

Pour la dernière ligne, la sonde a besoin d'une **seconde carte réseau attachée au sous-réseau isolé**. Si la sonde n'y est pas connectée, le script fonctionne quand même : CP23 et CP30 sont simplement rapportés en `SKIP`.

## 4. Comptes

Les identifiants sont demandés à l'exécution (ou fournis via `-VbrCredential`, `-PrismCredential`, et `-AhvCredential` pour 12.x) :

| Système | Rôle minimal |
|---|---|
| Veeam Backup & Replication | 13.x : un rôle autorisé à **lire les points de restauration et lancer des restaurations de VM Nutanix AHV** (Veeam Restore Operator, ou un rôle RBAC personnalisé à périmètre restreint introduit en 13.1). 12.x : Veeam Restore Operator. |
| Appliance Veeam Plug-in for Nutanix AHV (**12.x uniquement**) | Compte autorisé à lancer une restauration de VM (Portal Administrator ou Restore Operator). |
| Prism Central | **Cluster Admin** ou rôle personnalisé avec *lecture VM / sous-réseau*, *mise à jour VM* (arrêt) et *suppression VM*. |

Utiliser des comptes de service dédiés. Pour les exécutions non supervisées, stocker les identifiants dans un coffre et les récupérer avec [Microsoft.PowerShell.SecretManagement](https://github.com/PowerShell/SecretManagement) :

```powershell
$vbr   = Get-Secret -Name RV-VBR   -AsPlainText:$false
$prism = Get-Secret -Name RV-Prism -AsPlainText:$false
.\Test-AhvBackupRestore.ps1 -VmNames SRV-A -Cleanup -VbrCredential $vbr -PrismCredential $prism
# 12.x : ajouter  -AhvCredential (Get-Secret -Name RV-AHV -AsPlainText:$false)
```

## 5. Installer le script

1. Copier `Test-AhvBackupRestore.ps1` et `RecoveryVerification.sample.json` dans un dossier de la sonde, par ex. `C:\Tools\RecoveryVerification\`.
2. Débloquer le fichier s'il a été téléchargé : `Unblock-File .\Test-AhvBackupRestore.ps1`.
3. Générer le modèle de configuration et le renseigner :

   ```powershell
   .\Test-AhvBackupRestore.ps1 -InitConfig
   notepad .\RecoveryVerification.json
   ```

   Ou copier l'exemple : `Copy-Item RecoveryVerification.sample.json RecoveryVerification.json`.
4. Lancer une simulation pour valider connectivité et configuration sans rien restaurer :

   ```powershell
   .\Test-AhvBackupRestore.ps1 -VmNames SRV-A -WhatIf -Verbose
   ```

   Les points de contrôle de pré-vol CP00–CP04 s'exécutent réellement ; les actions de restauration sont seulement affichées.

## 6. Certificats TLS

Tous les appels d'API utilisent `-SkipCertificateCheck` car les composants Veeam et Nutanix sont généralement livrés avec des certificats auto-signés. S'ils portent des certificats de confiance et que vous souhaitez une validation stricte, retirer `SkipCertificateCheck = $true` dans `Invoke-Api`, `Connect-Vbr` et `Connect-AhvAppliance`.

## Étape suivante

Lire le [Guide utilisateur](guide-utilisateur.md).
