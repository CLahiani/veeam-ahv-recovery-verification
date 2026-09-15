<#
MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

<#
.SYNOPSIS
    [EN] Scripted Recovery Verification for Nutanix AHV with Veeam Backup & Replication.
    [FR] Recovery Verification scriptée pour Nutanix AHV avec Veeam Backup & Replication.

    [EN] Restores a sample of VMs from their latest Veeam restore points into an isolated AHV
         subnet, checks that they boot and that their services respond, removes the test VMs,
         then produces an HTML / CSV / JSON report. Console output and reports are available in
         English or French (-Language, auto-detected from the system culture by default).
    [FR] Restaure un échantillon de VM depuis leurs derniers points de restauration Veeam vers un
         sous-réseau AHV isolé, vérifie qu'elles démarrent et que leurs services répondent,
         supprime les VM de test, puis produit un rapport HTML / CSV / JSON. Console et rapports
         en anglais ou en français (-Language, détecté depuis la culture système par défaut).

.DESCRIPTION
    ══════════════════════════════════════════════════════════════════════════════════════════
    [EN] WHY
    SureBackup / Virtual Lab is not available for Nutanix AHV. This script reproduces the
    verification logic (restore, boot, tests, cleanup, report) through the public Veeam and
    Nutanix REST APIs.

    [FR] POURQUOI
    SureBackup / Virtual Lab n'est pas disponible pour Nutanix AHV. Ce script reproduit la
    logique de vérification (restauration, démarrage, tests, nettoyage, rapport) au travers des
    API REST publiques de Veeam et de Nutanix.
    ══════════════════════════════════════════════════════════════════════════════════════════

    [EN] STEPS
      Step 0  PRE-FLIGHT     Authentication (VBR, AHV appliance, Prism Central) and environment
                             checks: restore target, subnet isolation, no foreign or leftover VMs.
      Step 1  RESTORE        Per VM: latest restore point (VBR API), RPO check, full restore via
                             the AHV appliance with every NIC remapped to the isolated subnet and
                             automatic power-on.
      Step 2  VERIFY         Session tracking (RTO), VM state in Prism (power state, NICs, IP
                             reported by Nutanix Guest Tools), ping and per-VM application checks
                             (TCP, HTTP, LDAP, DNS, SQL).
      Step 3  CLEANUP        Power off and delete the test VMs (-Cleanup).
      Step 4  REPORT         HTML (summary + details), CSV, JSON, transcript. Exit code 0 = all
                             OK, 1 = at least one checkpoint failed, 2 = blocking pre-flight error.

    [FR] ÉTAPES
      Étape 0  PRÉ-VOL       Authentification (VBR, appliance AHV, Prism Central) et contrôle de
                             l'environnement : cible, isolement du sous-réseau, absence de VM
                             étrangères ou résiduelles.
      Étape 1  RESTAURATION  Par VM : dernier point de restauration (API VBR), contrôle du RPO,
                             restauration complète via l'appliance AHV avec remappage de toutes
                             les cartes réseau vers le sous-réseau isolé et démarrage automatique.
      Étape 2  VÉRIFICATION  Suivi des sessions (RTO), état de la VM dans Prism (power state,
                             cartes réseau, IP remontée par les Nutanix Guest Tools), ping et
                             contrôles applicatifs par VM (TCP, HTTP, LDAP, DNS, SQL).
      Étape 3  NETTOYAGE     Arrêt et suppression des VM de test (-Cleanup).
      Étape 4  RAPPORT       HTML (synthèse + détail), CSV, JSON, journal. Code de sortie 0 = tout
                             OK, 1 = au moins un point de contrôle en échec, 2 = erreur bloquante.

    CHECKPOINTS / POINTS DE CONTRÔLE  (OK / KO / WARN / SKIP)
      CP00  Authentication VBR / AHV / Prism            | Authentification VBR / AHV / Prism
      CP01  Cluster, container, isolated subnet exist   | Cluster, conteneur, sous-réseau présents
      CP02  Subnet is not external / routed  (blocking) | Sous-réseau ni externe ni routé (bloquant)
      CP03  No foreign VM on the isolated subnet        | Aucune VM hors périmètre sur le sous-réseau
      CP04  No leftover test VM               (blocking) | Aucune VM de test résiduelle (bloquant)
      CP10  Restore point found                         | Point de restauration trouvé
      CP11  Restore point age <= RPO target             | Âge du point de restauration <= RPO
      CP12  Restore session Success / Warning           | Session de restauration Success / Warning
      CP13  Restore duration <= RTO target              | Durée de restauration <= RTO
      CP20  VM powered on                               | VM démarrée
      CP21  All NICs on the isolated subnet (guardrail) | Toutes les NIC sur le sous-réseau isolé
      CP22  IP reported by Nutanix Guest Tools          | IP remontée par les Nutanix Guest Tools
      CP23  Ping from the probe (-PingCheck)            | Ping depuis la sonde (-PingCheck)
      CP30  Application checks (one CP per test)        | Contrôles applicatifs (un CP par test)
      CP40  Test VM deleted (-Cleanup)                  | VM de test supprimée (-Cleanup)

    [EN] PREREQUISITES
      - PowerShell 7.2 or later.
      - An isolated AHV subnet (non-routed VLAN, no gateway) created in Prism.
      - A "probe" machine connected to that subnet to run the script, or at least for CP23 / CP30
        (otherwise they stay SKIP).
      - Accounts: VBR (Veeam Restore Operator role), Veeam Plug-in for Nutanix AHV appliance,
        Prism Central (Cluster Admin or equivalent with VM create / delete rights).
      - PowerShell module "SqlServer" only if Sql checks are defined.

    [FR] PRÉREQUIS
      - PowerShell 7.2 ou supérieur.
      - Un sous-réseau AHV isolé (VLAN non routé, sans passerelle) créé dans Prism.
      - Une machine « sonde » connectée à ce sous-réseau pour exécuter le script, ou au moins pour
        CP23 / CP30 (sinon ils restent en SKIP).
      - Comptes : VBR (rôle Veeam Restore Operator), appliance Veeam Plug-in for Nutanix AHV,
        Prism Central (Cluster Admin ou équivalent avec création / suppression de VM).
      - Module PowerShell « SqlServer » uniquement si des contrôles Sql sont définis.

    [EN] QUICK START
      1. Generate the configuration template:  .\Test-AhvBackupRestore.ps1 -InitConfig
      2. Edit RecoveryVerification.json (servers, target, thresholds, application checks).
      3. Run:  .\Test-AhvBackupRestore.ps1 -VmNames SRV-A,SRV-B -Cleanup
      4. Open the HTML report in -ReportDir.
      Credentials are prompted, or passed with -VbrCredential / -AhvCredential / -PrismCredential
      (e.g. from a vault via Microsoft.PowerShell.SecretManagement).

    [FR] DÉMARRAGE RAPIDE
      1. Générer le modèle de configuration :  .\Test-AhvBackupRestore.ps1 -InitConfig
      2. Renseigner RecoveryVerification.json (serveurs, cible, seuils, contrôles applicatifs).
      3. Lancer :  .\Test-AhvBackupRestore.ps1 -VmNames SRV-A,SRV-B -Cleanup
      4. Ouvrir le rapport HTML dans -ReportDir.
      Les identifiants sont demandés, ou fournis via -VbrCredential / -AhvCredential / -PrismCredential
      (par exemple depuis un coffre : Microsoft.PowerShell.SecretManagement).

    REFERENCES / RÉFÉRENCES
      - Veeam Backup & Replication REST API     https://helpcenter.veeam.com/references/vbr
      - Veeam Plug-in for Nutanix AHV REST API   https://helpcenter.veeam.com/references/vbahv
      - Nutanix Prism Central v3 API             https://www.nutanix.dev

    [EN] DISCLAIMER  Illustrative example, provided without warranty. Validate in a test environment
         first. API response field names may vary between versions; affected lines are tagged "# [API]".
    [FR] AVERTISSEMENT  Exemple illustratif, sans garantie. À valider en recette. Les noms de champs
         des réponses d'API peuvent varier selon les versions ; lignes concernées marquées "# [API]".

.PARAMETER VmNames
    [EN] Source VM names to verify (as shown in Veeam).   [FR] Noms des VM sources (tels qu'affichés dans Veeam).

.PARAMETER ConfigPath
    [EN] JSON configuration file. Command-line parameters override the file.
    [FR] Fichier de configuration JSON. Les paramètres de ligne de commande ont priorité.

.PARAMETER InitConfig
    [EN] Write a configuration template to -ConfigPath and exit.
    [FR] Écrit un modèle de configuration dans -ConfigPath puis s'arrête.

.PARAMETER Language
    [EN] Output language: en or fr. Default: system culture (fr-* -> fr, otherwise en).
    [FR] Langue des sorties : en ou fr. Défaut : culture système (fr-* -> fr, sinon en).

.PARAMETER PingCheck
    [EN] Enable CP23 (ping the restored VM from this machine).   [FR] Active CP23 (ping depuis cette machine).

.PARAMETER Cleanup
    [EN] Delete test VMs at the end (and leftovers from previous runs).
    [FR] Supprime les VM de test à la fin (et les résiduelles des exécutions précédentes).

.PARAMETER FailOnWarning
    [EN] Treat WARN as failure for the exit code.   [FR] Considère WARN comme un échec pour le code de sortie.

.PARAMETER ReportDir
    [EN] Output folder for reports and transcript.   [FR] Dossier de sortie des rapports et du journal.

.EXAMPLE
    .\Test-AhvBackupRestore.ps1 -InitConfig
    [EN] Generate the configuration template.   [FR] Génère le modèle de configuration.

.EXAMPLE
    .\Test-AhvBackupRestore.ps1 -VmNames SRV-AD01,SRV-FILE01 -PingCheck -Cleanup -Language en

.EXAMPLE
    # [EN] Rotation: 3 different VMs each day from a list.  [FR] Rotation : 3 VM différentes par jour.
    $all = Get-Content .\vms.txt ; $d = (Get-Date).DayOfYear
    $sample = 0..2 | ForEach-Object { $all[($d * 3 + $_) % $all.Count] }
    .\Test-AhvBackupRestore.ps1 -VmNames $sample -Cleanup

.EXAMPLE
    .\Test-AhvBackupRestore.ps1 -VmNames SRV-A -Cleanup -WhatIf
    [EN] Show restore / delete actions without executing them.   [FR] Simule sans exécuter.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string[]] $VmNames,

    [string] $ConfigPath = ".\RecoveryVerification.json",
    [switch] $InitConfig,
    [ValidateSet('en', 'fr')]
    [string] $Language,

    # --- Optional overrides of the configuration file / Surcharges facultatives ---
    [string] $VbrServer,
    [int]    $VbrPort,
    [string] $AhvAppliance,
    [string] $AhvApiVersion,
    [string] $PrismCentral,
    [int]    $PrismPort,
    [string] $TargetClusterName,
    [string] $IsolatedNetworkName,
    [string] $StorageContainerName,
    [string] $VmNamePrefix,
    [int]    $MaxRestorePointAgeHours,
    [int]    $MaxRestoreMinutes,
    [int]    $BootTimeoutMinutes,

    # --- Credentials (prompted if omitted) / Identifiants (demandés si absents) ---
    [PSCredential] $VbrCredential,
    [PSCredential] $AhvCredential,
    [PSCredential] $PrismCredential,

    # --- Options ---
    [switch] $PingCheck,
    [switch] $Cleanup,
    [switch] $FailOnWarning,
    [string] $ReportDir = ".\Reports"
)

#requires -Version 7.2
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# =====================================================================================
#region  Localisation / Localization
# =====================================================================================

if (-not $Language) { $Language = if ((Get-Culture).Name -like 'fr*') { 'fr' } else { 'en' } }

$Strings = @{
    en = @{
        # Steps
        Step0 = 'Step 0 - Pre-flight: connections and environment checks'
        Step1 = 'Step 1 - Restoring {0} VM(s) into the isolated subnet'
        Step2 = 'Step 2 - Verifying restored VMs'
        Step4 = 'Step 4 - Report'
        # Checkpoint labels
        CP00 = 'Authentication VBR / AHV appliance / Prism Central'
        CP01 = 'Cluster, storage container and isolated subnet present'
        CP02 = 'Isolated subnet is non-routed'
        CP03 = 'No foreign VM on the isolated subnet'
        CP04 = 'No leftover test VM'
        CP10 = 'Restore point found'
        CP11 = 'Restore point age <= {0} h'
        CP12 = 'Restore session completed'
        CP12Start = 'Restore started'
        CP13 = 'Restore duration <= {0} min'
        CP20 = 'VM powered on'
        CP21 = 'NICs only on the isolated subnet'
        CP22 = 'IP address reported (Nutanix Guest Tools)'
        CP23 = 'Ping from the probe'
        CP30 = 'Application checks'
        CP30Item = 'Application: {0}'
        CP40 = 'Test VM deleted'
        PostRestore = 'Post-restore check'
        Verify = 'Verification'
        # Details
        D_ClusterUnknown = "cluster '{0}' unknown to the AHV appliance"
        D_SubnetMissing = "subnet '{0}' not found - create it in Prism (non-routed VLAN) then rescan the appliance"
        D_ContainerMissing = "storage container '{0}' not found"
        D_SubnetNotInPrism = 'subnet not found in Prism Central'
        D_SubnetRouted = 'is_external={0}, gateway={1} - restored VMs could be exposed'
        D_SubnetOk = 'is_external=false, no gateway'
        D_ForeignVms = 'VMs present: {0}'
        D_LeftoverDeleteFailed = 'could not delete: {0}'
        D_LeftoverDeleted = '{0} leftover VM(s) deleted: {1}'
        D_LeftoverFound = '{0} leftover VM(s) - rerun with -Cleanup: {1}'
        D_NoRestorePoint = 'no Nutanix AHV restore point for this name'
        D_NoRestorePointShort = 'no restore point'
        D_CreatedOn = 'created on {0}'
        D_RpoMissed = ' - RPO missed, check the backup job'
        D_SessionStarted = '    -> session {0} started'
        D_LaunchFailed = 'launch failed'
        D_SessionFailed = 'status = {0} after {1} min (see the session in the Veeam console)'
        D_RestoreFailed = 'restore failed'
        D_RtoMissed = ' - RTO target exceeded'
        D_VmNotFound = "VM '{0}' not found in Prism"
        D_VmNotFoundShort = 'VM not found'
        D_PowerState = 'power_state = {0}'
        D_NicLeak = 'NIC outside the isolated subnet - VM powered off immediately'
        D_NoNic = 'no NIC attached'
        D_NoIp = 'no IP - NGT missing, no DHCP on the isolated subnet, or OS not booted'
        D_NoIpShort = 'no IP address'
        D_PingOff = '-PingCheck not enabled'
        D_NoChecks = 'no check defined (AppChecks section)'
        D_CleanupOff = '-Cleanup not enabled (VM kept for analysis)'
        D_CleanupFailed = "{0} - delete '{1}' manually in Prism"
        D_Unexpected = 'unexpected error: {0}'
        D_WhatIf = 'WhatIf'
        # Messages
        M_NeedVm = 'Specify at least one VM with -VmNames (or use -InitConfig to create the configuration).'
        M_ConfigWritten = 'Configuration template written to {0}. Fill it in, then rerun with -VmNames.'
        M_ConfigExists = 'File {0} exists. Overwrite?'
        M_ConfigUnreadable = 'Unreadable configuration ({0}): {1}'
        M_ConfigLoaded = 'Configuration loaded from {0}'
        M_NoConfig = 'No configuration file ({0}): defaults in use. Generate one with -InitConfig.'
        M_CredVbr = 'Veeam Backup & Replication account ({0})'
        M_CredAhv = 'Veeam Plug-in for Nutanix AHV appliance account ({0})'
        M_CredPrism = 'Prism Central account ({0})'
        M_PreflightAbort = 'Stopped in pre-flight: fix the KO items above and rerun.'
        M_Fatal = 'Fatal error: {0}'
        M_ReportFailed = 'Report generation failed: {0}'
        M_Failures = '{0} checkpoint(s) failed.'
        M_AllOk = 'All checkpoints passed: the verified restore points boot and respond.'
        M_ShutdownFailed = 'Safety power-off of {0} failed: {1}'
        M_ApiFailed = 'Call {0} {1} failed (HTTP {2}){3}. {4}'
        M_Http401 = ': invalid credentials or expired token'
        M_Http403 = ': insufficient rights for this operation'
        M_Http404 = ': resource not found (check API version and object IDs)'
        M_Retry = 'Attempt {0} failed ({1}) - retrying in {2} s'
        M_DeleteAction = 'Power off and delete test VM'
        M_RestoreAction = 'Restore to {0} on {1}'
        # Report
        R_Title = 'Recovery Verification - Nutanix AHV'
        R_Run = 'Run'
        R_Cluster = 'Cluster'
        R_Subnet = 'Isolated subnet'
        R_Fail = 'FAILED - {0} checkpoint(s) KO'
        R_Warn = 'PASSED WITH WARNINGS - {0} WARN'
        R_Ok = 'PASSED - all checkpoints OK'
        R_KpiVms = 'VMs verified'; R_KpiOk = 'checks OK'; R_KpiWarn = 'warnings'; R_KpiKo = 'failures'
        R_KpiRpo = 'RPO target'; R_KpiRto = 'RTO target'
        R_Summary = 'Summary per VM'
        R_Details = 'Checkpoint details'
        R_H_Vm = 'VM'; R_H_Age = 'Restore point age (h)'; R_H_Dur = 'Restore duration (min)'; R_H_Ip = 'IP'
        R_H_Result = 'Result'; R_H_Time = 'Time'; R_H_Check = 'Check'; R_H_Status = 'Status'; R_H_Detail = 'Detail'
        R_Footer = 'Generated by Test-AhvBackupRestore.ps1 (MIT license). Related files: {0}, {1}, transcript {2}.'
        R_OkWarn = 'OK (warnings)'
    }
    fr = @{
        Step0 = "Étape 0 - Pré-vol : connexions et contrôle de l'environnement"
        Step1 = 'Étape 1 - Restauration de {0} VM vers le sous-réseau isolé'
        Step2 = 'Étape 2 - Vérification des VM restaurées'
        Step4 = 'Étape 4 - Rapport'
        CP00 = 'Authentification VBR / appliance AHV / Prism Central'
        CP01 = 'Cluster, conteneur de stockage et sous-réseau isolé présents'
        CP02 = 'Sous-réseau isolé non routé'
        CP03 = 'Aucune VM hors périmètre sur le sous-réseau isolé'
        CP04 = 'Aucune VM de test résiduelle'
        CP10 = 'Point de restauration trouvé'
        CP11 = 'Âge du point de restauration <= {0} h'
        CP12 = 'Session de restauration terminée'
        CP12Start = 'Restauration lancée'
        CP13 = 'Durée de restauration <= {0} min'
        CP20 = 'VM démarrée'
        CP21 = 'Cartes réseau sur le sous-réseau isolé uniquement'
        CP22 = 'Adresse IP remontée (Nutanix Guest Tools)'
        CP23 = 'Ping depuis la sonde'
        CP30 = 'Contrôles applicatifs'
        CP30Item = 'Applicatif : {0}'
        CP40 = 'VM de test supprimée'
        PostRestore = 'Contrôle post-restauration'
        Verify = 'Vérification'
        D_ClusterUnknown = "cluster '{0}' inconnu de l'appliance AHV"
        D_SubnetMissing = "sous-réseau '{0}' introuvable - le créer dans Prism (VLAN non routé) puis relancer un rescan de l'appliance"
        D_ContainerMissing = "conteneur de stockage '{0}' introuvable"
        D_SubnetNotInPrism = 'sous-réseau introuvable dans Prism Central'
        D_SubnetRouted = "is_external={0}, passerelle={1} - risque d'exposition des VM restaurées"
        D_SubnetOk = 'is_external=false, aucune passerelle'
        D_ForeignVms = 'VM présentes : {0}'
        D_LeftoverDeleteFailed = 'suppression impossible : {0}'
        D_LeftoverDeleted = '{0} VM résiduelle(s) supprimée(s) : {1}'
        D_LeftoverFound = '{0} VM résiduelle(s) - relancer avec -Cleanup : {1}'
        D_NoRestorePoint = 'aucun point de restauration Nutanix AHV pour ce nom'
        D_NoRestorePointShort = 'pas de point de restauration'
        D_CreatedOn = 'créé le {0}'
        D_RpoMissed = ' - RPO non tenu, vérifier le job de sauvegarde'
        D_SessionStarted = '    -> session {0} démarrée'
        D_LaunchFailed = 'échec au lancement'
        D_SessionFailed = 'statut = {0} après {1} min (voir la session dans la console Veeam)'
        D_RestoreFailed = 'restauration en échec'
        D_RtoMissed = ' - RTO cible dépassé'
        D_VmNotFound = "VM '{0}' introuvable dans Prism"
        D_VmNotFoundShort = 'VM introuvable'
        D_PowerState = 'power_state = {0}'
        D_NicLeak = 'carte réseau hors sous-réseau isolé - arrêt immédiat de la VM'
        D_NoNic = 'aucune carte réseau attachée'
        D_NoIp = 'aucune IP - NGT absent, pas de DHCP sur le sous-réseau isolé ou OS non démarré'
        D_NoIpShort = "pas d'adresse IP"
        D_PingOff = 'option -PingCheck non activée'
        D_NoChecks = 'aucun contrôle défini (section AppChecks)'
        D_CleanupOff = 'option -Cleanup non activée (VM conservée pour analyse)'
        D_CleanupFailed = "{0} - supprimer manuellement '{1}' dans Prism"
        D_Unexpected = 'erreur inattendue : {0}'
        D_WhatIf = 'WhatIf'
        M_NeedVm = 'Indiquez au moins une VM avec -VmNames (ou utilisez -InitConfig pour créer la configuration).'
        M_ConfigWritten = 'Modèle de configuration écrit dans {0}. Renseignez-le puis relancez avec -VmNames.'
        M_ConfigExists = "Le fichier {0} existe. L'écraser ?"
        M_ConfigUnreadable = 'Configuration illisible ({0}) : {1}'
        M_ConfigLoaded = 'Configuration chargée depuis {0}'
        M_NoConfig = 'Aucun fichier de configuration ({0}) : valeurs par défaut utilisées. Générez-en un avec -InitConfig.'
        M_CredVbr = 'Compte Veeam Backup & Replication ({0})'
        M_CredAhv = 'Compte appliance Veeam Plug-in for Nutanix AHV ({0})'
        M_CredPrism = 'Compte Prism Central ({0})'
        M_PreflightAbort = 'Arrêt en pré-vol : corrigez les points KO ci-dessus puis relancez.'
        M_Fatal = 'Erreur bloquante : {0}'
        M_ReportFailed = 'Génération des rapports en échec : {0}'
        M_Failures = '{0} point(s) de contrôle en échec.'
        M_AllOk = 'Tous les points de contrôle sont passés : les points de restauration vérifiés démarrent et répondent.'
        M_ShutdownFailed = 'Arrêt de sécurité de {0} impossible : {1}'
        M_ApiFailed = 'Appel {0} {1} en échec (HTTP {2}){3}. {4}'
        M_Http401 = ' : identifiants invalides ou jeton expiré'
        M_Http403 = ' : droits insuffisants pour cette opération'
        M_Http404 = " : ressource introuvable (vérifier la version d'API et les identifiants d'objets)"
        M_Retry = 'Tentative {0} échouée ({1}) - nouvelle tentative dans {2} s'
        M_DeleteAction = 'Arrêt et suppression de la VM de test'
        M_RestoreAction = 'Restauration vers {0} sur {1}'
        R_Title = 'Recovery Verification - Nutanix AHV'
        R_Run = 'Exécution'
        R_Cluster = 'Cluster'
        R_Subnet = 'Sous-réseau isolé'
        R_Fail = 'ÉCHEC - {0} point(s) de contrôle KO'
        R_Warn = 'SUCCÈS AVEC AVERTISSEMENTS - {0} WARN'
        R_Ok = 'SUCCÈS - tous les points de contrôle sont passés'
        R_KpiVms = 'VM vérifiées'; R_KpiOk = 'contrôles OK'; R_KpiWarn = 'avertissements'; R_KpiKo = 'échecs'
        R_KpiRpo = 'RPO cible'; R_KpiRto = 'RTO cible'
        R_Summary = 'Synthèse par VM'
        R_Details = 'Détail des points de contrôle'
        R_H_Vm = 'VM'; R_H_Age = 'Âge du point de restauration (h)'; R_H_Dur = 'Durée de restauration (min)'; R_H_Ip = 'IP'
        R_H_Result = 'Résultat'; R_H_Time = 'Heure'; R_H_Check = 'Contrôle'; R_H_Status = 'Statut'; R_H_Detail = 'Détail'
        R_Footer = 'Généré par Test-AhvBackupRestore.ps1 (licence MIT). Fichiers associés : {0}, {1}, journal {2}.'
        R_OkWarn = 'OK (avertissements)'
    }
}
$T = $Strings[$Language]

function L {
    <# Localized string with optional format arguments. / Chaîne localisée avec arguments de format. #>
    param([Parameter(Mandatory)][string]$Key, [Parameter(Position = 1)][object[]]$Params = @())
    $s = $T[$Key]; if (-not $s) { return $Key }
    if ($Params.Count) { return ($s -f $Params) } else { return $s }
}

#endregion

# =====================================================================================
#region  Configuration
# =====================================================================================

$DefaultConfig = [ordered]@{
    Veeam = [ordered]@{
        VbrServer     = "vbr.example.local"        # Veeam Backup & Replication server
        VbrPort       = 9419                       # VBR REST API port (default 9419)
        VbrApiVersion = "1.2-rev0"                 # x-api-version header expected by VBR
        AhvAppliance  = "veeam-ahv.example.local"  # Veeam Plug-in for Nutanix AHV appliance
        AhvApiVersion = "v8"                       # Plug-in API prefix (v8, v9...)
    }
    Nutanix = [ordered]@{
        PrismCentral = "prism.example.local"
        PrismPort    = 9440
    }
    Target = [ordered]@{
        ClusterName          = "CLUSTER-01"                 # AHV cluster used for the restore
        IsolatedNetworkName  = "VLAN-RecoveryVerification"  # Isolated, non-routed subnet
        StorageContainerName = "default-container"
        VmNamePrefix         = "RV-"                        # Prefix of test VMs
    }
    Thresholds = [ordered]@{
        MaxRestorePointAgeHours = 30   # RPO target: max restore point age
        MaxRestoreMinutes       = 45   # RTO target: max restore duration
        BootTimeoutMinutes      = 15   # Max wait for boot / IP
        PollIntervalSeconds     = 20
    }
    # Application checks per VM. Key "*" applies to every VM.
    # Types: Tcp (Port) | Http (Url with {ip}, ExpectedStatus) | Ldap (Port) | Dns (Name) | Sql (Port, Query)
    AppChecks = [ordered]@{
        "*"         = @( [ordered]@{ Type = "Tcp"; Port = 3389; Label = "RDP (Windows)" } )
        "SRV-AD01"  = @( [ordered]@{ Type = "Ldap"; Port = 389; Label = "LDAP" },
                         [ordered]@{ Type = "Dns"; Name = "example.local"; Label = "DNS zone" } )
        "SRV-WEB01" = @( [ordered]@{ Type = "Http"; Url = "https://{ip}/health"; ExpectedStatus = 200; Label = "Health" } )
        "SRV-SQL01" = @( [ordered]@{ Type = "Sql"; Port = 1433; Query = "SELECT COUNT(*) FROM sys.databases WHERE state_desc='ONLINE'"; Label = "Online databases" } )
    }
}

if ($InitConfig) {
    if ((Test-Path $ConfigPath) -and -not $PSCmdlet.ShouldContinue((L M_ConfigExists $ConfigPath), 'Confirmation')) { return }
    $DefaultConfig | ConvertTo-Json -Depth 6 | Set-Content -Path $ConfigPath -Encoding UTF8
    Write-Host (L M_ConfigWritten $ConfigPath) -ForegroundColor Green
    return
}

function Merge-Config {
    <# defaults <- JSON file <- command line / défauts <- fichier JSON <- ligne de commande #>
    param($Defaults, $FilePath, $Bound)
    $cfg = $Defaults
    if (Test-Path $FilePath) {
        try   { $file = Get-Content $FilePath -Raw | ConvertFrom-Json -AsHashtable }
        catch { throw (L M_ConfigUnreadable $FilePath, $_.Exception.Message) }
        foreach ($section in $file.Keys) {
            if ($section -eq 'AppChecks') { $cfg.AppChecks = $file.AppChecks; continue }
            if (-not $cfg.Contains($section)) { $cfg[$section] = [ordered]@{} }
            foreach ($k in $file[$section].Keys) { $cfg[$section][$k] = $file[$section][$k] }
        }
        Write-Verbose (L M_ConfigLoaded $FilePath)
    }
    else { Write-Warning (L M_NoConfig $FilePath) }

    $map = @{
        VbrServer = 'Veeam.VbrServer'; VbrPort = 'Veeam.VbrPort'; AhvAppliance = 'Veeam.AhvAppliance'; AhvApiVersion = 'Veeam.AhvApiVersion'
        PrismCentral = 'Nutanix.PrismCentral'; PrismPort = 'Nutanix.PrismPort'
        TargetClusterName = 'Target.ClusterName'; IsolatedNetworkName = 'Target.IsolatedNetworkName'
        StorageContainerName = 'Target.StorageContainerName'; VmNamePrefix = 'Target.VmNamePrefix'
        MaxRestorePointAgeHours = 'Thresholds.MaxRestorePointAgeHours'; MaxRestoreMinutes = 'Thresholds.MaxRestoreMinutes'; BootTimeoutMinutes = 'Thresholds.BootTimeoutMinutes'
    }
    foreach ($p in $map.Keys) {
        if ($Bound.ContainsKey($p)) { $sec, $key = $map[$p].Split('.'); $cfg[$sec][$key] = $Bound[$p] }
    }
    return $cfg
}

if (-not $VmNames -or $VmNames.Count -eq 0) { throw (L M_NeedVm) }
$Cfg = Merge-Config $DefaultConfig $ConfigPath $PSBoundParameters
if (-not $VbrCredential)   { $VbrCredential   = Get-Credential -Message (L M_CredVbr   $Cfg.Veeam.VbrServer) }
if (-not $AhvCredential)   { $AhvCredential   = Get-Credential -Message (L M_CredAhv   $Cfg.Veeam.AhvAppliance) }
if (-not $PrismCredential) { $PrismCredential = Get-Credential -Message (L M_CredPrism $Cfg.Nutanix.PrismCentral) }

#endregion

# =====================================================================================
#region  Logging and checkpoints / Journalisation et points de contrôle
# =====================================================================================

$RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
$LogPath = Join-Path $ReportDir "RecoveryVerification-$RunId.log"
Start-Transcript -Path $LogPath -Append | Out-Null

$Checkpoints = [System.Collections.Generic.List[object]]::new()

function Write-Step { param([string]$Title) Write-Host "`n=== $Title ===" -ForegroundColor Cyan }

function Add-Checkpoint {
    <# Record and display a checkpoint. / Enregistre et affiche un point de contrôle. #>
    param(
        [Parameter(Mandatory)][string] $Id,
        [string] $Vm = '-',
        [Parameter(Mandatory)][string] $Label,
        [Parameter(Mandatory)][ValidateSet('OK','KO','WARN','SKIP')][string] $Status,
        [string] $Detail = '',
        [double] $Value = [double]::NaN
    )
    $Checkpoints.Add([pscustomobject]@{
        RunId = $RunId; Time = (Get-Date -Format 's'); CP = $Id; VM = $Vm
        Label = $Label; Status = $Status; Value = $Value; Detail = $Detail
    })
    $color = switch ($Status) { 'OK' { 'Green' } 'KO' { 'Red' } 'WARN' { 'Yellow' } default { 'DarkGray' } }
    $suffix = if ($Detail) { " - $Detail" } else { '' }
    Write-Host ("  [{0}] {1,-4} {2,-16} {3}{4}" -f $Id, $Status, $Vm, $Label, $suffix) -ForegroundColor $color
}

function Skip-RemainingChecks {
    param([string]$Vm, [string]$Reason)
    foreach ($cp in 'CP13','CP20','CP21','CP22','CP23','CP30','CP40') { Add-Checkpoint $cp $Vm (L PostRestore) SKIP $Reason }
}

#endregion

# =====================================================================================
#region  API access (retries, explicit errors) / Accès API (tentatives, erreurs explicites)
# =====================================================================================

function Invoke-Api {
    <#
      Generic REST call: 3 retries on network / 5xx / 429 errors, readable error with HTTP code and body.
      Appel REST générique : 3 tentatives sur erreurs réseau / 5xx / 429, erreur lisible avec code HTTP et corps.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PUT','DELETE')][string] $Method,
        [Parameter(Mandatory)][string] $Uri,
        [hashtable] $Headers = @{},
        $Body,
        [int] $Retries = 3
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $p = @{ Method = $Method; Uri = $Uri; Headers = $Headers; SkipCertificateCheck = $true; ContentType = 'application/json'; TimeoutSec = 120 }
            if ($null -ne $Body) { $p.Body = ($Body | ConvertTo-Json -Depth 12) }
            Write-Verbose "$Method $Uri"
            return Invoke-RestMethod @p
        }
        catch {
            $status = $null; $content = ''
            if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
                $status = [int]$_.Exception.Response.StatusCode
                try { $content = $_.ErrorDetails.Message } catch {}
            }
            $retryable = (-not $status) -or $status -ge 500 -or $status -eq 429
            if ($retryable -and $attempt -lt $Retries) {
                Write-Verbose (L M_Retry $attempt, $status, (5 * $attempt)); Start-Sleep -Seconds (5 * $attempt); continue
            }
            $hint = switch ($status) { 401 { L M_Http401 } 403 { L M_Http403 } 404 { L M_Http404 } default { '' } }
            throw (L M_ApiFailed $Method, $Uri, $status, $hint, $content).Trim()
        }
    }
}

function Get-Items {
    <# Normalize collections returned flat or under .results / .data / .entities #>
    param($Response)
    foreach ($prop in 'results','data','entities') {
        if ($Response -is [pscustomobject] -and $Response.PSObject.Properties[$prop]) { return @($Response.$prop) }
    }
    return @($Response)
}

function Connect-Vbr {
    param($Server, $Port, $ApiVersion, [PSCredential]$Credential)
    $base = "https://$Server`:$Port/api"
    $tok = Invoke-RestMethod -Method Post -Uri "$base/oauth2/token" -SkipCertificateCheck -TimeoutSec 60 `
        -Headers @{ 'x-api-version' = $ApiVersion } -ContentType 'application/x-www-form-urlencoded' `
        -Body @{ grant_type = 'password'; username = $Credential.UserName; password = $Credential.GetNetworkCredential().Password }
    return @{ Base = $base; Headers = @{ Authorization = "Bearer $($tok.access_token)"; 'x-api-version' = $ApiVersion } }
}

function Connect-AhvAppliance {
    param($Server, $ApiVersion, [PSCredential]$Credential)
    $base = "https://$Server/api"
    $tok = Invoke-RestMethod -Method Post -Uri "$base/oauth2/token" -SkipCertificateCheck -TimeoutSec 60 `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body @{ grant_type = 'password'; username = $Credential.UserName; password = $Credential.GetNetworkCredential().Password }
    return @{ Base = "$base/$ApiVersion"; Headers = @{ Authorization = "Bearer $($tok.access_token)" } }
}

function Connect-Prism {
    param($Server, $Port, [PSCredential]$Credential)
    $base = "https://$Server`:$Port/api/nutanix/v3"
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"))
    $ctx  = @{ Base = $base; Headers = @{ Authorization = "Basic $auth" } }
    Invoke-Api POST "$base/clusters/list" $ctx.Headers @{ kind = 'cluster' } | Out-Null   # connection test
    return $ctx
}

#endregion

# =====================================================================================
#region  Business functions / Fonctions métier
# =====================================================================================

function Get-LatestRestorePoint {
    <# Latest Veeam restore point of a Nutanix AHV VM (VBR API), exact name match. #>
    param($Vbr, [string]$VmName)
    $uri = "$($Vbr.Base)/v1/objectRestorePoints?nameFilter=$([uri]::EscapeDataString($VmName))&platformNameFilter=NutanixAhv&orderColumn=CreationTime&orderAsc=false&limit=5"
    $rps = Get-Items (Invoke-Api GET $uri $Vbr.Headers) | Where-Object { $_.name -eq $VmName }   # [API] nameFilter is "contains"
    return $rps | Sort-Object creationTime -Descending | Select-Object -First 1
}

function Start-IsolatedRestore {
    <# Full VM restore into the isolated subnet through the AHV appliance. Returns session id. #>
    param($Ahv, $RestorePoint, $Cluster, $Container, $Network, [string]$TargetName, [string]$Reason)
    $nics = Get-Items (Invoke-Api GET "$($Ahv.Base)/restorePoints/$($RestorePoint.id)/networkAdapters" $Ahv.Headers)
    $nicMap = @($nics | ForEach-Object { @{ value = @{ networkId = $Network.id; ipAddresses = @(); macAddress = $_.macAddress } } })
    $body = @{
        restorePointId = $RestorePoint.id; restoreToOriginal = $false; targetVmClusterId = $Cluster.id
        targetVmName = $TargetName; storageContainerId = $Container.id; networkAdapters = $nicMap
        powerOnVmAfterRestore = $true; restoreVmCategories = $false; reason = $Reason
    }
    $resp = Invoke-Api POST "$($Ahv.Base)/restorePoints/restore" $Ahv.Headers $body
    return @{ SessionId = $resp.sessionId; NicCount = $nicMap.Count }
}

function Wait-RestoreSession {
    <# Wait for an appliance session to finish. Returns final status or 'Timeout'. #>
    param($Ahv, [string]$SessionId, [int]$TimeoutMinutes, [int]$PollSeconds)
    $pending = @('Running','InProgress','None','Pending',$null)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        Start-Sleep -Seconds $PollSeconds
        $s = Invoke-Api GET "$($Ahv.Base)/sessions/$SessionId" $Ahv.Headers
        $status = if ($s.PSObject.Properties['result'] -and $s.result) { $s.result } else { $s.status }   # [API]
    } while ($status -in $pending -and (Get-Date) -lt $deadline)
    if ($status -in $pending) { return 'Timeout' }
    return $status
}

function Get-PrismVm {
    param($Prism, [string]$Name)
    $r = Invoke-Api POST "$($Prism.Base)/vms/list" $Prism.Headers @{ kind = 'vm'; filter = "vm_name==$Name" }
    return (Get-Items $r) | Where-Object { $_.status.name -eq $Name } | Select-Object -First 1
}

function Wait-VmBoot {
    <# Wait until the VM is ON and reports an IP (NGT). Returns @{ Vm; Power; Ip } #>
    param($Prism, [string]$Name, [int]$TimeoutMinutes, [int]$PollSeconds)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes); $vm = $null; $power = $null; $ip = $null
    do {
        Start-Sleep -Seconds $PollSeconds
        $vm = Get-PrismVm $Prism $Name
        if ($vm) {
            $power = $vm.status.resources.power_state
            $ip = @($vm.status.resources.nic_list | ForEach-Object { $_.ip_endpoint_list } | ForEach-Object { $_.ip } | Where-Object { $_ }) | Select-Object -First 1
        }
    } while (-not $ip -and (Get-Date) -lt $deadline)
    return @{ Vm = $vm; Power = $power; Ip = $ip }
}

function Set-PrismVmPower {
    param($Prism, [string]$Uuid, [ValidateSet('ON','OFF')][string]$State)
    $cur = Invoke-Api GET "$($Prism.Base)/vms/$Uuid" $Prism.Headers
    if ($cur.status.resources.power_state -eq $State) { return }
    $spec = [pscustomobject]@{ metadata = $cur.metadata; spec = $cur.spec }
    $spec.spec.resources.power_state = $State
    Invoke-Api PUT "$($Prism.Base)/vms/$Uuid" $Prism.Headers $spec | Out-Null
}

function Remove-PrismVm {
    [CmdletBinding(SupportsShouldProcess)]
    param($Prism, [string]$Uuid, [string]$Name)
    if ($PSCmdlet.ShouldProcess($Name, (L M_DeleteAction))) {
        Set-PrismVmPower $Prism $Uuid 'OFF'
        Start-Sleep -Seconds 20
        Invoke-Api DELETE "$($Prism.Base)/vms/$Uuid" $Prism.Headers | Out-Null
    }
}

function Test-AppCheck {
    <# Run one application check. Returns @{ Ok = $true/$false/$null(SKIP); Detail } #>
    param($Check, [string]$Ip)
    try {
        switch ($Check['Type']) {
            'Tcp' {
                $ok = Test-NetConnection -ComputerName $Ip -Port $Check['Port'] -WarningAction SilentlyContinue -InformationLevel Quiet
                return @{ Ok = [bool]$ok; Detail = "tcp/$($Check['Port'])" }
            }
            'Ldap' {
                $ok = Test-NetConnection -ComputerName $Ip -Port $Check['Port'] -WarningAction SilentlyContinue -InformationLevel Quiet
                if (-not $ok) { return @{ Ok = $false; Detail = "tcp/$($Check['Port']) closed" } }
                $conn = [System.DirectoryServices.Protocols.LdapConnection]::new("$Ip`:$($Check['Port'])")
                $conn.AuthType = 'Anonymous'; $conn.Bind()
                return @{ Ok = $true; Detail = 'anonymous RootDSE bind OK' }
            }
            'Http' {
                $url = $Check['Url'] -replace '\{ip\}', $Ip
                $r = Invoke-WebRequest -Uri $url -SkipCertificateCheck -TimeoutSec 15 -UseBasicParsing
                $expected = if ($Check['ExpectedStatus']) { [int]$Check['ExpectedStatus'] } else { 200 }
                return @{ Ok = ([int]$r.StatusCode -eq $expected); Detail = "HTTP $($r.StatusCode) $url" }
            }
            'Dns' {
                $r = Resolve-DnsName -Name $Check['Name'] -Server $Ip -DnsOnly
                return @{ Ok = ($r.Count -gt 0); Detail = "$($Check['Name']) -> $Ip" }
            }
            'Sql' {
                if (-not (Get-Module -ListAvailable SqlServer)) { return @{ Ok = $null; Detail = 'SqlServer module missing' } }
                $res = Invoke-Sqlcmd -ServerInstance "$Ip,$($Check['Port'])" -Query $Check['Query'] -TrustServerCertificate -ConnectionTimeout 15
                return @{ Ok = ($null -ne $res); Detail = "result = $($res[0])" }
            }
            default { return @{ Ok = $null; Detail = "unknown check type: $($Check['Type'])" } }
        }
    }
    catch { return @{ Ok = $false; Detail = $_.Exception.Message } }
}

function Get-ChecksForVm {
    param($AppChecks, [string]$Vm)
    $list = @()
    if ($AppChecks.Contains('*')) { $list += @($AppChecks['*']) }
    if ($AppChecks.Contains($Vm)) { $list += @($AppChecks[$Vm]) }
    return $list
}

#endregion

# =====================================================================================
#region  Reports / Rapports
# =====================================================================================

function New-Summary {
    param($VmNames, $Checkpoints, [switch]$FailOnWarning)
    foreach ($vm in $VmNames) {
        $cps = $Checkpoints | Where-Object VM -eq $vm
        $ko  = @($cps | Where-Object Status -eq 'KO').Count
        $wa  = @($cps | Where-Object Status -eq 'WARN').Count
        [pscustomobject]@{
            VM               = $vm
            RestorePointAgeH = ($cps | Where-Object CP -eq 'CP11' | Select-Object -First 1).Value
            RestoreMinutes   = ($cps | Where-Object CP -eq 'CP13' | Select-Object -First 1).Value
            IP               = ($cps | Where-Object { $_.CP -eq 'CP22' -and $_.Status -eq 'OK' } | Select-Object -First 1).Detail
            KO = $ko; WARN = $wa
            Result = if ($ko -gt 0 -or ($FailOnWarning -and $wa -gt 0)) { 'KO' } elseif ($wa -gt 0) { L R_OkWarn } else { 'OK' }
        }
    }
}

function Export-Reports {
    param($Summary, $Checkpoints, $Cfg, [string]$Dir, [string]$RunId, [string[]]$VmNames)
    $csv  = Join-Path $Dir "RecoveryVerification-$RunId.csv"
    $json = Join-Path $Dir "RecoveryVerification-$RunId.json"
    $html = Join-Path $Dir "RecoveryVerification-$RunId.html"

    $Checkpoints | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    [ordered]@{ RunId = $RunId; Date = (Get-Date -Format 's'); Language = $Language; Target = $Cfg.Target; Thresholds = $Cfg.Thresholds; Summary = $Summary; Checkpoints = $Checkpoints } |
        ConvertTo-Json -Depth 6 | Set-Content -Path $json -Encoding UTF8

    $totKo = @($Checkpoints | Where-Object Status -eq 'KO').Count
    $totWa = @($Checkpoints | Where-Object Status -eq 'WARN').Count
    $totOk = @($Checkpoints | Where-Object Status -eq 'OK').Count
    $banner = if ($totKo -gt 0) { @{ Text = (L R_Fail $totKo); Color = '#c62828' } }
              elseif ($totWa -gt 0) { @{ Text = (L R_Warn $totWa); Color = '#ef6c00' } }
              else { @{ Text = (L R_Ok); Color = '#2e7d32' } }
    $enc = { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
    $okWarnLabel = L R_OkWarn

    $rowsSummary = ($Summary | ForEach-Object {
        $cls = if ($_.Result -eq 'KO') { 'ko' } elseif ($_.Result -eq $okWarnLabel) { 'warn' } else { 'ok' }
        "<tr><td>$(& $enc $_.VM)</td><td>$(& $enc $_.RestorePointAgeH)</td><td>$(& $enc $_.RestoreMinutes)</td><td>$(& $enc $_.IP)</td><td>$($_.KO)</td><td>$($_.WARN)</td><td class='$cls'>$(& $enc $_.Result)</td></tr>"
    }) -join "`n"
    $rowsCp = ($Checkpoints | ForEach-Object {
        "<tr><td>$(& $enc $_.Time)</td><td>$(& $enc $_.CP)</td><td>$(& $enc $_.VM)</td><td>$(& $enc $_.Label)</td><td class='$($_.Status.ToLower())'>$(& $enc $_.Status)</td><td>$(& $enc $_.Detail)</td></tr>"
    }) -join "`n"

    @"
<!DOCTYPE html><html lang="$Language"><head><meta charset="utf-8"><title>$(L R_Title) - $RunId</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#222;margin:24px;background:#fafafa}
h1{font-size:20px;margin:0 0 4px}h2{font-size:16px;margin:24px 0 8px;border-bottom:1px solid #ddd;padding-bottom:4px}
.banner{color:#fff;padding:10px 14px;border-radius:4px;font-weight:600;margin:12px 0;background:$($banner.Color)}
.kpi{display:inline-block;background:#fff;border:1px solid #e0e0e0;border-radius:4px;padding:8px 14px;margin:0 8px 8px 0}.kpi b{font-size:18px;display:block}
table{border-collapse:collapse;width:100%;background:#fff}th,td{border:1px solid #e0e0e0;padding:6px 8px;text-align:left;vertical-align:top}
th{background:#f0f0f0}td.ok{background:#e8f5e9;color:#2e7d32;font-weight:600}td.ko{background:#ffebee;color:#c62828;font-weight:600}
td.warn{background:#fff3e0;color:#ef6c00;font-weight:600}td.skip{color:#888}small{color:#666}
</style></head><body>
<h1>$(L R_Title)</h1>
<small>$(L R_Run) $RunId &middot; $(Get-Date -Format 'yyyy-MM-dd HH:mm') &middot; $(L R_Cluster) $(& $enc $Cfg.Target.ClusterName) &middot; $(L R_Subnet) $(& $enc $Cfg.Target.IsolatedNetworkName) &middot; VBR $(& $enc $Cfg.Veeam.VbrServer)</small>
<div class="banner">$(& $enc $banner.Text)</div>
<div class="kpi"><b>$($VmNames.Count)</b>$(L R_KpiVms)</div><div class="kpi"><b>$totOk</b>$(L R_KpiOk)</div>
<div class="kpi"><b>$totWa</b>$(L R_KpiWarn)</div><div class="kpi"><b>$totKo</b>$(L R_KpiKo)</div>
<div class="kpi"><b>$($Cfg.Thresholds.MaxRestorePointAgeHours) h</b>$(L R_KpiRpo)</div><div class="kpi"><b>$($Cfg.Thresholds.MaxRestoreMinutes) min</b>$(L R_KpiRto)</div>
<h2>$(L R_Summary)</h2>
<table><tr><th>$(L R_H_Vm)</th><th>$(L R_H_Age)</th><th>$(L R_H_Dur)</th><th>$(L R_H_Ip)</th><th>KO</th><th>WARN</th><th>$(L R_H_Result)</th></tr>
$rowsSummary</table>
<h2>$(L R_Details)</h2>
<table><tr><th>$(L R_H_Time)</th><th>CP</th><th>$(L R_H_Vm)</th><th>$(L R_H_Check)</th><th>$(L R_H_Status)</th><th>$(L R_H_Detail)</th></tr>
$rowsCp</table>
<p><small>$(L R_Footer (Split-Path $csv -Leaf), (Split-Path $json -Leaf), (Split-Path $LogPath -Leaf))</small></p>
</body></html>
"@ | Set-Content -Path $html -Encoding UTF8

    return @{ Csv = $csv; Json = $json; Html = $html }
}

#endregion

# =====================================================================================
#region  Execution / Exécution
# =====================================================================================

$exitCode = 0
try {
    # ---------------------------------------------------------------------------------
    Write-Step (L Step0)
    # ---------------------------------------------------------------------------------
    try {
        $Vbr   = Connect-Vbr          $Cfg.Veeam.VbrServer $Cfg.Veeam.VbrPort $Cfg.Veeam.VbrApiVersion $VbrCredential
        $Ahv   = Connect-AhvAppliance $Cfg.Veeam.AhvAppliance $Cfg.Veeam.AhvApiVersion $AhvCredential
        $Prism = Connect-Prism        $Cfg.Nutanix.PrismCentral $Cfg.Nutanix.PrismPort $PrismCredential
        Add-Checkpoint CP00 -Label (L CP00) -Status OK
    }
    catch { Add-Checkpoint CP00 -Label (L CP00) -Status KO -Detail $_.Exception.Message; throw [System.Exception]::new('PREFLIGHT', $_.Exception) }

    try {
        $cluster = Get-Items (Invoke-Api GET "$($Ahv.Base)/clusters" $Ahv.Headers) | Where-Object name -eq $Cfg.Target.ClusterName | Select-Object -First 1
        if (-not $cluster) { throw (L D_ClusterUnknown $Cfg.Target.ClusterName) }
        $network = Get-Items (Invoke-Api GET "$($Ahv.Base)/clusters/$($cluster.id)/networks" $Ahv.Headers) | Where-Object name -eq $Cfg.Target.IsolatedNetworkName | Select-Object -First 1
        if (-not $network) { throw (L D_SubnetMissing $Cfg.Target.IsolatedNetworkName) }
        $container = Get-Items (Invoke-Api GET "$($Ahv.Base)/clusters/$($cluster.id)/storageContainers" $Ahv.Headers) | Where-Object name -eq $Cfg.Target.StorageContainerName | Select-Object -First 1
        if (-not $container) { throw (L D_ContainerMissing $Cfg.Target.StorageContainerName) }
        Add-Checkpoint CP01 -Label (L CP01) -Status OK -Detail "$($cluster.name) / $($container.name) / $($network.name)"
    }
    catch { Add-Checkpoint CP01 -Label (L CP01) -Status KO -Detail $_.Exception.Message; throw [System.Exception]::new('PREFLIGHT', $_.Exception) }

    # CP02 - real subnet isolation (blocking)
    $subnet = Get-Items (Invoke-Api POST "$($Prism.Base)/subnets/list" $Prism.Headers @{ kind = 'subnet'; filter = "name==$($Cfg.Target.IsolatedNetworkName)" }) |
              Where-Object { $_.status.name -eq $Cfg.Target.IsolatedNetworkName } | Select-Object -First 1
    if (-not $subnet) { Add-Checkpoint CP02 -Label (L CP02) -Status KO -Detail (L D_SubnetNotInPrism); throw [System.Exception]::new('PREFLIGHT') }
    $res = $subnet.status.resources
    $gateway = if ($res.PSObject.Properties['ip_config'] -and $res.ip_config) { $res.ip_config.default_gateway_ip } else { $null }
    if ($res.is_external -eq $true -or $gateway) {
        Add-Checkpoint CP02 -Label (L CP02) -Status KO -Detail (L D_SubnetRouted $res.is_external, $gateway); throw [System.Exception]::new('PREFLIGHT')
    }
    Add-Checkpoint CP02 -Label (L CP02) -Status OK -Detail (L D_SubnetOk)

    # CP03 / CP04 - subnet occupants and leftover test VMs
    $allVms  = Get-Items (Invoke-Api POST "$($Prism.Base)/vms/list" $Prism.Headers @{ kind = 'vm'; length = 500 })
    $prefix  = $Cfg.Target.VmNamePrefix
    $onIso   = $allVms | Where-Object { @($_.status.resources.nic_list | ForEach-Object { $_.subnet_reference.uuid }) -contains $subnet.metadata.uuid }
    $foreign = @($onIso | Where-Object { $_.status.name -notlike "$prefix*" })
    if ($foreign.Count) { Add-Checkpoint CP03 -Label (L CP03) -Status KO -Detail (L D_ForeignVms ($foreign.status.name -join ', ')) }
    else                { Add-Checkpoint CP03 -Label (L CP03) -Status OK }

    $stale = @($allVms | Where-Object { $_.status.name -like "$prefix*" })
    if ($stale.Count -eq 0) { Add-Checkpoint CP04 -Label (L CP04) -Status OK }
    elseif ($Cleanup) {
        $failed = @()
        foreach ($sv in $stale) { try { Remove-PrismVm $Prism $sv.metadata.uuid $sv.status.name } catch { $failed += $sv.status.name } }
        if ($failed.Count) { Add-Checkpoint CP04 -Label (L CP04) -Status KO -Detail (L D_LeftoverDeleteFailed ($failed -join ', ')); throw [System.Exception]::new('PREFLIGHT') }
        Add-Checkpoint CP04 -Label (L CP04) -Status WARN -Detail (L D_LeftoverDeleted $stale.Count, ($stale.status.name -join ', '))
    }
    else { Add-Checkpoint CP04 -Label (L CP04) -Status KO -Detail (L D_LeftoverFound $stale.Count, ($stale.status.name -join ', ')); throw [System.Exception]::new('PREFLIGHT') }

    # ---------------------------------------------------------------------------------
    Write-Step (L Step1 $VmNames.Count)
    # ---------------------------------------------------------------------------------
    $sessions = @{}
    foreach ($vm in $VmNames) {
        try {
            $rp = Get-LatestRestorePoint $Vbr $vm
            if (-not $rp) { Add-Checkpoint CP10 $vm (L CP10) KO (L D_NoRestorePoint); Skip-RemainingChecks $vm (L D_NoRestorePointShort); continue }
            Add-Checkpoint CP10 $vm (L CP10) OK (L D_CreatedOn $rp.creationTime)

            $ageH  = [math]::Round(((Get-Date) - [datetime]$rp.creationTime).TotalHours, 1)
            $rpoOk = $ageH -le $Cfg.Thresholds.MaxRestorePointAgeHours
            Add-Checkpoint CP11 $vm (L CP11 $Cfg.Thresholds.MaxRestorePointAgeHours) ($rpoOk ? 'OK' : 'KO') "$ageH h$(if (-not $rpoOk) { L D_RpoMissed })" $ageH

            $target = "$prefix$vm"
            if ($PSCmdlet.ShouldProcess($vm, (L M_RestoreAction $target, $network.name))) {
                $r = Start-IsolatedRestore $Ahv $rp $cluster $container $network $target "Recovery Verification $RunId"
                $sessions[$vm] = @{ SessionId = $r.SessionId; NicCount = $r.NicCount; Started = Get-Date; Target = $target }
                Write-Host (L D_SessionStarted $r.SessionId) -ForegroundColor DarkGray
            }
            else { Skip-RemainingChecks $vm (L D_WhatIf) }
        }
        catch { Add-Checkpoint CP12 $vm (L CP12Start) KO $_.Exception.Message; Skip-RemainingChecks $vm (L D_LaunchFailed) }
    }

    # ---------------------------------------------------------------------------------
    Write-Step (L Step2)
    # ---------------------------------------------------------------------------------
    $poll = $Cfg.Thresholds.PollIntervalSeconds
    foreach ($vm in $sessions.Keys) {
        $s = $sessions[$vm]; $vmUuid = $null
        try {
            # CP12 / CP13
            $status = Wait-RestoreSession $Ahv $s.SessionId ($Cfg.Thresholds.MaxRestoreMinutes + $Cfg.Thresholds.BootTimeoutMinutes) $poll
            $durMin = [math]::Round(((Get-Date) - $s.Started).TotalMinutes, 1)
            if ($status -notin @('Success','Warning')) {
                Add-Checkpoint CP12 $vm (L CP12) KO (L D_SessionFailed $status, $durMin); Skip-RemainingChecks $vm (L D_RestoreFailed); continue
            }
            Add-Checkpoint CP12 $vm (L CP12) ($status -eq 'Success' ? 'OK' : 'WARN') $status
            $rtoOk = $durMin -le $Cfg.Thresholds.MaxRestoreMinutes
            Add-Checkpoint CP13 $vm (L CP13 $Cfg.Thresholds.MaxRestoreMinutes) ($rtoOk ? 'OK' : 'WARN') "$durMin min$(if (-not $rtoOk) { L D_RtoMissed })" $durMin

            # CP20 / CP21 / CP22
            $boot = Wait-VmBoot $Prism $s.Target $Cfg.Thresholds.BootTimeoutMinutes $poll
            if (-not $boot.Vm) { Add-Checkpoint CP20 $vm (L CP20) KO (L D_VmNotFound $s.Target); Skip-RemainingChecks $vm (L D_VmNotFoundShort); continue }
            $vmUuid = $boot.Vm.metadata.uuid
            Add-Checkpoint CP20 $vm (L CP20) ($boot.Power -eq 'ON' ? 'OK' : 'KO') (L D_PowerState $boot.Power)

            $nicSubnets = @($boot.Vm.status.resources.nic_list | ForEach-Object { $_.subnet_reference.uuid } | Select-Object -Unique)
            $leak = @($nicSubnets | Where-Object { $_ -ne $subnet.metadata.uuid })
            if ($leak.Count) {
                Add-Checkpoint CP21 $vm (L CP21) KO (L D_NicLeak)
                try { Set-PrismVmPower $Prism $vmUuid 'OFF' } catch { Write-Warning (L M_ShutdownFailed $s.Target, $_.Exception.Message) }
            }
            elseif ($nicSubnets.Count -eq 0 -and $s.NicCount -gt 0) { Add-Checkpoint CP21 $vm (L CP21) WARN (L D_NoNic) }
            else { Add-Checkpoint CP21 $vm (L CP21) OK }

            if ($boot.Ip) { Add-Checkpoint CP22 $vm (L CP22) OK $boot.Ip }
            else { Add-Checkpoint CP22 $vm (L CP22) ($boot.Power -eq 'ON' ? 'WARN' : 'KO') (L D_NoIp) }

            # CP23
            if (-not $PingCheck)   { Add-Checkpoint CP23 $vm (L CP23) SKIP (L D_PingOff) }
            elseif (-not $boot.Ip) { Add-Checkpoint CP23 $vm (L CP23) SKIP (L D_NoIpShort) }
            else { $p = Test-Connection -TargetName $boot.Ip -Count 2 -Quiet -ErrorAction SilentlyContinue; Add-Checkpoint CP23 $vm (L CP23) ($p ? 'OK' : 'KO') $boot.Ip }

            # CP30
            $checks = Get-ChecksForVm $Cfg.AppChecks $vm
            if (-not $boot.Ip)           { Add-Checkpoint CP30 $vm (L CP30) SKIP (L D_NoIpShort) }
            elseif ($checks.Count -eq 0) { Add-Checkpoint CP30 $vm (L CP30) SKIP (L D_NoChecks) }
            else {
                foreach ($c in $checks) {
                    $r  = Test-AppCheck $c $boot.Ip
                    $st = if ($null -eq $r.Ok) { 'SKIP' } elseif ($r.Ok) { 'OK' } else { 'KO' }
                    $label = if ($c['Label']) { $c['Label'] } else { $c['Type'] }
                    Add-Checkpoint CP30 $vm (L CP30Item $label) $st $r.Detail
                }
            }
        }
        catch { Add-Checkpoint CP20 $vm (L Verify) KO (L D_Unexpected $_.Exception.Message) }
        finally {
            # Step 3 - Cleanup (always attempted) / Étape 3 - Nettoyage (toujours tenté)
            if (-not $Cleanup)    { Add-Checkpoint CP40 $vm (L CP40) SKIP (L D_CleanupOff) }
            elseif (-not $vmUuid) { Add-Checkpoint CP40 $vm (L CP40) SKIP (L D_VmNotFoundShort) }
            else {
                try   { Remove-PrismVm $Prism $vmUuid $s.Target; Add-Checkpoint CP40 $vm (L CP40) OK $s.Target }
                catch { Add-Checkpoint CP40 $vm (L CP40) KO (L D_CleanupFailed $_.Exception.Message, $s.Target) }
            }
        }
    }
}
catch {
    if ($_.Exception.Message -eq 'PREFLIGHT') { Write-Host "`n$(L M_PreflightAbort)" -ForegroundColor Red }
    else { Write-Host "`n$(L M_Fatal $_.Exception.Message)" -ForegroundColor Red; Write-Verbose $_.ScriptStackTrace }
    $exitCode = 2
}
finally {
    # ---------------------------------------------------------------------------------
    Write-Step (L Step4)
    # ---------------------------------------------------------------------------------
    try {
        $summary = @(New-Summary $VmNames $Checkpoints -FailOnWarning:$FailOnWarning)
        $files   = Export-Reports $summary $Checkpoints $Cfg $ReportDir $RunId $VmNames
        $summary | Format-Table VM, RestorePointAgeH, RestoreMinutes, IP, KO, WARN, Result -AutoSize | Out-String | Write-Host
        Write-Host "HTML : $($files.Html)`nCSV  : $($files.Csv)`nJSON : $($files.Json)`nLog  : $LogPath"
    }
    catch { Write-Warning (L M_ReportFailed $_.Exception.Message) }

    if ($exitCode -eq 0) {
        $failures = @($Checkpoints | Where-Object { $_.Status -eq 'KO' -or ($FailOnWarning -and $_.Status -eq 'WARN') }).Count
        if ($failures -gt 0) { Write-Host "`n$(L M_Failures $failures)" -ForegroundColor Red; $exitCode = 1 }
        else { Write-Host "`n$(L M_AllOk)" -ForegroundColor Green }
    }
    Stop-Transcript | Out-Null
}
exit $exitCode

#endregion
