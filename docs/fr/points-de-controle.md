# Référence des points de contrôle

[← Configuration](configuration.md) · [README](../../README.md) · 🇬🇧 [English version](../en/checkpoints.md)

Chaque vérification est enregistrée comme un **point de contrôle** avec un statut `OK`, `KO`, `WARN` ou `SKIP`, et apparaît dans la console, les fichiers CSV / JSON et le rapport HTML. `Value` contient la mesure pour CP11 (heures) et CP13 (minutes).

Les points de contrôle **bloquants** arrêtent l'exécution en pré-vol (code de sortie 2). Les autres continuent ; un `KO` sur une VM saute les contrôles restants de cette VM uniquement.

## Étape 0 — Pré-vol (une fois par exécution)

| CP | Contrôle | OK | WARN | KO | Bloquant |
|---|---|---|---|---|---|
| **CP00** | Authentification VBR, plug-in AHV (13.x intégré / 12.x appliance), Prism Central | Tout OK ; le détail indique le mode | — | Une connexion a échoué (HTTP 401 / réseau) | ✔ |
| **CP01** | Cluster, conteneur de stockage et sous-réseau isolé présents dans l'inventaire de l'appliance | Les trois trouvés par nom | — | L'un manque (`Detail` indique lequel) | ✔ |
| **CP02** | Le sous-réseau isolé est **non routé** (Prism : `is_external = false`, pas de passerelle par défaut) | Les deux conditions vraies | — | Sous-réseau introuvable dans Prism, ou externe, ou avec passerelle | ✔ |
| **CP03** | Aucune VM hors périmètre sur le sous-réseau isolé | Aucune VM, ou uniquement des VM `<préfixe>*` | — | Des VM ne commençant pas par le préfixe y sont attachées (listées) | — |
| **CP04** | Aucune VM de test résiduelle (`<préfixe>*`) d'une exécution précédente | Aucune | Résiduelles trouvées **et supprimées** (`--cleanup`) | Résiduelles trouvées sans `--cleanup`, ou suppression en échec | ✔ |

## Étape 1 — Restauration (par VM)

| CP | Contrôle | OK | WARN | KO | SKIP |
|---|---|---|---|---|---|
| **CP10** | Dernier point de restauration Nutanix AHV trouvé dans VBR (nom exact) | Trouvé, `Detail` = date de création | — | Aucun point de restauration → CP restants `SKIP` | — |
| **CP11** | Âge du point de restauration ≤ `MaxRestorePointAgeHours` (**RPO**) | Âge dans la cible | — | Plus ancien que la cible (`RPO non tenu, vérifier le job de sauvegarde`) | — |
| **CP12** | Session de restauration lancée et terminée en `Success` / `Warning` | `Success` | `Warning` | Échec au lancement, `Failed`, ou `Timeout` après `MaxRestoreMinutes + BootTimeoutMinutes` → CP restants `SKIP` | `--dry-run` |

## Étape 2 — Vérification (par VM)

| CP | Contrôle | OK | WARN | KO | SKIP |
|---|---|---|---|---|---|
| **CP13** | Durée de restauration ≤ `MaxRestoreMinutes` (**RTO**) | Dans la cible | Dépassée (`RTO cible dépassé`) | — | Restauration en échec |
| **CP20** | VM de test trouvée dans Prism et `power_state = ON` | `ON` | — | VM introuvable, ou pas `ON` après `BootTimeoutMinutes` | Restauration en échec |
| **CP21** | **Garde-fou** — toutes les cartes réseau de la VM de test sont sur le sous-réseau isolé | Toutes sur le sous-réseau isolé | Aucune carte attachée alors que la source en avait | Une carte est sur un autre sous-réseau → **VM arrêtée immédiatement** | Restauration en échec |
| **CP22** | Adresse IP remontée par les Nutanix Guest Tools | IP présente (`Detail` = IP) | VM `ON` mais pas d'IP (NGT absent, pas de DHCP, OS en démarrage) | VM pas `ON` et pas d'IP | Restauration en échec |
| **CP23** | Ping depuis la sonde (`--ping-check`) | 2 réponses écho | — | Aucune réponse | `--ping-check` désactivé, ou pas d'IP |
| **CP30** | Contrôles applicatifs — **un point de contrôle par contrôle** (`Applicatif : <Label>`) | Contrôle réussi | — | Contrôle en échec (`Detail` = raison) | Pas d'IP, aucun contrôle défini, module python (`ldap3` / `dnspython` / `pymssql`) absent, type inconnu |

## Étape 3 — Nettoyage (par VM, toujours tenté)

| CP | Contrôle | OK | KO | SKIP |
|---|---|---|---|---|
| **CP40** | VM de test arrêtée et supprimée (`--cleanup`) | Supprimée | Suppression en échec (`supprimer manuellement '…' dans Prism`) | `--cleanup` désactivé (VM conservée), ou VM jamais trouvée |

## Résultat par VM et code de sortie

| Situation | `Result` par VM | Code de sortie |
|---|---|---|
| Aucun `KO`, aucun `WARN` | `OK` | `0` |
| `WARN` uniquement, sans `--fail-on-warning` | `OK (avertissements)` | `0` |
| `WARN` uniquement, avec `--fail-on-warning` | `KO` | `1` |
| Au moins un `KO` | `KO` | `1` |
| Échec bloquant en pré-vol ou erreur fatale | — | `2` |

## Correspondance avec les questions d'audit

| Question d'audit | Preuve |
|---|---|
| Les sauvegardes existent et respectent le RPO | CP10 + CP11 avec `Value` (heures) dans CSV / JSON |
| Les sauvegardes sont restaurables dans le RTO | CP12 + CP13 avec `Value` (minutes) |
| Les systèmes restaurés démarrent et sont joignables | CP20 + CP22 + CP23 |
| Les applications fonctionnent après restauration | CP30 par service |
| Les tests n'exposent jamais la production | CP02 + CP03 + CP21 |
| L'environnement de test est nettoyé | CP04 + CP40 |

Conserver le rapport HTML (et éventuellement le CSV) de chaque exécution comme preuve ; le `RunId` dans le nom de fichier relie les quatre fichiers entre eux.
