# Installation et prérequis

[← README](../../README.md) · [Guide utilisateur →](guide-utilisateur.md) · 🇬🇧 [English version](../en/installation.md)

## 1. Logiciels

| Composant | Exigence |
|---|---|
| PowerShell | **7.2 ou supérieur** (`pwsh`). Windows PowerShell 5.1 n'est pas pris en charge (`SkipCertificateCheck`, opérateur ternaire, `ConvertFrom-Json -AsHashtable`). |
| OS de la machine sonde | Windows recommandé. `Test-NetConnection` et `Resolve-DnsName` (utilisés par les contrôles Tcp / Ldap / Dns) sont des cmdlets Windows. Sous Linux, seuls les contrôles Http et Sql fonctionnent. |
| Module `SqlServer` | Uniquement si des contrôles applicatifs `Sql` sont définis : `Install-Module SqlServer -Scope CurrentUser` |
| Veeam Backup & Replication | API REST activée (port **9419** par défaut). Testé avec l'en-tête de version `1.2-rev0` ; ajuster `Veeam.VbrApiVersion` selon votre version. |
| Veeam Plug-in for Nutanix AHV | Appliance joignable en HTTPS ; préfixe d'API `v8` (ou `v9`…) dans `Veeam.AhvApiVersion`. |
| Nutanix Prism Central | API v3 (port **9440** par défaut). |

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
| Serveur VBR | 9419/tcp | Rechercher les derniers points de restauration |
| Appliance Veeam AHV | 443/tcp | Lancer et suivre les restaurations |
| Prism Central | 9440/tcp | Inspecter VM / sous-réseaux, arrêter, supprimer |
| Sous-réseau isolé | ICMP, ports applicatifs | Ping CP23 et contrôles applicatifs CP30 |

Pour la dernière ligne, la sonde a besoin d'une **seconde carte réseau attachée au sous-réseau isolé**. Si la sonde n'y est pas connectée, le script fonctionne quand même : CP23 et CP30 sont simplement rapportés en `SKIP`.

## 4. Comptes

Trois jeux d'identifiants sont demandés à l'exécution (ou fournis via `-VbrCredential`, `-AhvCredential`, `-PrismCredential`) :

| Système | Rôle minimal |
|---|---|
| Veeam Backup & Replication | **Veeam Restore Operator** (lecture des points de restauration). |
| Appliance Veeam Plug-in for Nutanix AHV | Compte autorisé à lancer une restauration de VM (Portal Administrator ou Restore Operator). |
| Prism Central | **Cluster Admin** ou rôle personnalisé avec *lecture VM / sous-réseau*, *mise à jour VM* (arrêt) et *suppression VM*. |

Utiliser des comptes de service dédiés. Pour les exécutions non supervisées, stocker les identifiants dans un coffre et les récupérer avec [Microsoft.PowerShell.SecretManagement](https://github.com/PowerShell/SecretManagement) :

```powershell
$vbr   = Get-Secret -Name RV-VBR   -AsPlainText:$false
$ahv   = Get-Secret -Name RV-AHV   -AsPlainText:$false
$prism = Get-Secret -Name RV-Prism -AsPlainText:$false
.\Test-AhvBackupRestore.ps1 -VmNames SRV-A -Cleanup -VbrCredential $vbr -AhvCredential $ahv -PrismCredential $prism
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

Tous les appels d'API utilisent `-SkipCertificateCheck` car les appliances Veeam et Nutanix sont généralement livrées avec des certificats auto-signés. Si vos appliances portent des certificats de confiance et que vous souhaitez une validation stricte, retirer `SkipCertificateCheck = $true` dans `Invoke-Api`, `Connect-Vbr` et `Connect-AhvAppliance`.

## Étape suivante

Lire le [Guide utilisateur](guide-utilisateur.md).
