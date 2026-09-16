#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ahv_backup_restore.py — Scripted Recovery Verification for Nutanix AHV with Veeam Backup & Replication
                        Recovery Verification scriptée pour Nutanix AHV avec Veeam Backup & Replication

MIT License — Copyright (c) 2026 — see LICENSE.

[EN] Restores a sample of VMs from their latest Veeam restore points into an ISOLATED AHV subnet, checks that
     they boot and that their services respond, removes the test VMs, then produces an HTML / CSV / JSON
     report. English or French output. Runs from any Linux or Windows machine with Python 3.9+ (the "probe").

     WHY  SureBackup / Virtual Lab is not available for Nutanix AHV. This tool reproduces the verification
     logic (restore, boot, tests, cleanup, report) through the public Veeam and Nutanix REST APIs.

     VEEAM VERSIONS (Veeam.AhvIntegrated)
       true  (default) VBR 13.x: the AHV plug-in is integrated into VBR (worker architecture). Its REST API is
                       served by the VBR server at /extension/<id>/api/v9 and accepts the VBR OAuth token.
       false           VBR 12.x: standalone Veeam Plug-in for Nutanix AHV appliance (REST API v8, own login).

[FR] Restaure un échantillon de VM depuis leurs derniers points de restauration Veeam vers un sous-réseau AHV
     ISOLÉ, vérifie qu'elles démarrent et que leurs services répondent, supprime les VM de test, puis produit
     un rapport HTML / CSV / JSON. Sortie en anglais ou français. S'exécute depuis toute machine Linux ou
     Windows avec Python 3.9+ (la « sonde »).

     POURQUOI  SureBackup / Virtual Lab n'est pas disponible pour Nutanix AHV. Cet outil reproduit la logique de
     vérification (restauration, démarrage, tests, nettoyage, rapport) via les API REST publiques Veeam et Nutanix.

CHECKPOINTS / POINTS DE CONTRÔLE (OK / KO / WARN / SKIP)
  CP00 Authentication VBR / AHV plug-in / Prism      CP20 VM powered on
  CP01 Cluster, container, isolated subnet present   CP21 All NICs on the isolated subnet (guardrail)
  CP02 Subnet not external / routed (blocking)       CP22 IP reported by Nutanix Guest Tools
  CP03 No foreign VM on the isolated subnet          CP23 Ping from the probe (--ping-check)
  CP04 No leftover test VM (blocking)                CP30 Application checks (one CP per check)
  CP10 Restore point found   CP11 Age <= RPO         CP40 Test VM deleted (--cleanup)
  CP12 Restore session Success/Warning   CP13 Restore duration <= RTO

QUICK START / DÉMARRAGE RAPIDE
  ./ahv_backup_restore.py --init-config           # then edit RecoveryVerification.json / puis renseigner
  ./ahv_backup_restore.py -v SRV-A -v SRV-B --cleanup --dry-run     # pre-flight only / pré-vol seul
  ./ahv_backup_restore.py -v SRV-A -v SRV-B --ping-check --cleanup  # real run / exécution réelle
Secrets: env VBR_USER / VBR_PASSWORD / PRISM_USER / PRISM_PASSWORD (+ AHV_USER / AHV_PASSWORD for 12.x),
or --secrets-file (JSON, mode 600), or prompt.

Exit code: 0 all OK | 1 at least one checkpoint failed | 2 blocking pre-flight / fatal error.
Requires Python 3.9+. Optional: dnspython (Dns), ldap3 (Ldap), pymssql (Sql).
Lines depending on API response field names are tagged "# [API]". Illustrative example, no warranty.
"""

from __future__ import annotations

import argparse
import base64
import csv
import getpass
import html
import json
import locale
import logging
import os
import platform
import socket
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

VERSION = "2.0.0"
AHV_EXTENSION_ID = "799a5a3e-ae1e-4eaf-86eb-8a9acc2670e2"   # Veeam Plug-in for Nutanix AHV extension id in VBR 13.x (fixed)

# =====================================================================================
# Localisation / Localization
# =====================================================================================

STRINGS: Dict[str, Dict[str, str]] = {
    "en": {
        "Step0": "Step 0 - Pre-flight: connections and environment checks",
        "Step1": "Step 1 - Restoring {0} VM(s) into the isolated subnet",
        "Step2": "Step 2 - Verifying restored VMs",
        "Step4": "Step 4 - Report",
        "CP00": "Authentication VBR / AHV plug-in / Prism Central",
        "CP01": "Cluster, storage container and isolated subnet present",
        "CP02": "Isolated subnet is non-routed",
        "CP03": "No foreign VM on the isolated subnet",
        "CP04": "No leftover test VM",
        "CP10": "Restore point found",
        "CP11": "Restore point age <= {0} h",
        "CP12": "Restore session completed",
        "CP12Start": "Restore started",
        "CP13": "Restore duration <= {0} min",
        "CP20": "VM powered on",
        "CP21": "NICs only on the isolated subnet",
        "CP22": "IP address reported (Nutanix Guest Tools)",
        "CP23": "Ping from the probe",
        "CP30": "Application checks",
        "CP30Item": "Application: {0}",
        "CP40": "Test VM deleted",
        "PostRestore": "Post-restore check",
        "Verify": "Verification",
        "D_Mode13": "VBR 13.x integrated plug-in ({0})",
        "D_Mode12": "12.x appliance {0} ({1})",
        "D_ClusterUnknown": "cluster '{0}' unknown to the AHV plug-in",
        "D_SubnetMissing": "subnet '{0}' not found - create it in Prism (non-routed VLAN) then rescan the Nutanix server in Veeam",
        "D_ContainerMissing": "storage container '{0}' not found",
        "D_SubnetNotInPrism": "subnet not found in Prism Central",
        "D_SubnetRouted": "is_external={0}, gateway={1} - restored VMs could be exposed",
        "D_SubnetOk": "is_external=false, no gateway",
        "D_ForeignVms": "VMs present: {0}",
        "D_LeftoverDeleteFailed": "could not delete: {0}",
        "D_LeftoverDeleted": "{0} leftover VM(s) deleted: {1}",
        "D_LeftoverFound": "{0} leftover VM(s) - rerun with --cleanup: {1}",
        "D_NoRestorePoint": "no Nutanix AHV restore point for this name",
        "D_NoRestorePointShort": "no restore point",
        "D_CreatedOn": "created on {0}",
        "D_RpoMissed": " - RPO missed, check the backup job",
        "D_SessionStarted": "    -> session {0} started",
        "D_LaunchFailed": "launch failed",
        "D_SessionFailed": "status = {0} after {1} min (see the session in the Veeam console)",
        "D_RestoreFailed": "restore failed",
        "D_RtoMissed": " - RTO target exceeded",
        "D_VmNotFound": "VM '{0}' not found in Prism",
        "D_VmNotFoundShort": "VM not found",
        "D_PowerState": "power_state = {0}",
        "D_NicLeak": "NIC outside the isolated subnet - VM powered off immediately",
        "D_NoNic": "no NIC attached",
        "D_NoIp": "no IP - NGT missing, no DHCP on the isolated subnet, or OS not booted",
        "D_NoIpShort": "no IP address",
        "D_PingOff": "--ping-check not enabled",
        "D_NoChecks": "no check defined (AppChecks section)",
        "D_CleanupOff": "--cleanup not enabled (VM kept for analysis)",
        "D_CleanupFailed": "{0} - delete '{1}' manually in Prism",
        "D_Unexpected": "unexpected error: {0}",
        "D_DryRun": "dry-run",
        "D_ModuleMissing": "python module '{0}' missing",
        "M_NeedVm": "Specify at least one VM with -v/--vm (or use --init-config to create the configuration).",
        "M_ConfigWritten": "Configuration template written to {0}. Fill it in, then rerun with -v.",
        "M_ConfigExists": "File {0} exists - use --force to overwrite.",
        "M_ConfigUnreadable": "Unreadable configuration ({0}): {1}",
        "M_NoConfig": "No configuration file ({0}): defaults in use. Generate one with --init-config.",
        "M_CredVbr": "Veeam Backup & Replication account for {0}",
        "M_CredAhv": "Veeam Plug-in for Nutanix AHV appliance account for {0}",
        "M_CredPrism": "Prism Central account for {0}",
        "M_PreflightAbort": "Stopped in pre-flight: fix the KO items above and rerun.",
        "M_Fatal": "Fatal error: {0}",
        "M_ReportFailed": "Report generation failed: {0}",
        "M_Failures": "{0} checkpoint(s) failed.",
        "M_AllOk": "All checkpoints passed: the verified restore points boot and respond.",
        "M_ShutdownFailed": "Safety power-off of {0} failed: {1}",
        "M_ApiFailed": "Call {0} {1} failed (HTTP {2}){3}. {4}",
        "M_Http401": ": invalid credentials or expired token",
        "M_Http403": ": insufficient rights for this operation",
        "M_Http404": ": resource not found (check API version and object IDs)",
        "M_Retry": "Attempt {0} failed ({1}) - retrying in {2} s",
        "M_DeleteAction": "Power off and delete test VM {0}",
        "M_RestoreAction": "Restore {0} to {1} on {2}",
        "R_Title": "Recovery Verification - Nutanix AHV",
        "R_Run": "Run", "R_Cluster": "Cluster", "R_Subnet": "Isolated subnet",
        "R_Fail": "FAILED - {0} checkpoint(s) KO", "R_Warn": "PASSED WITH WARNINGS - {0} WARN", "R_Ok": "PASSED - all checkpoints OK",
        "R_KpiVms": "VMs verified", "R_KpiOk": "checks OK", "R_KpiWarn": "warnings", "R_KpiKo": "failures",
        "R_KpiRpo": "RPO target", "R_KpiRto": "RTO target",
        "R_Summary": "Summary per VM", "R_Details": "Checkpoint details",
        "R_H_Vm": "VM", "R_H_Age": "Restore point age (h)", "R_H_Dur": "Restore duration (min)", "R_H_Ip": "IP",
        "R_H_Result": "Result", "R_H_Time": "Time", "R_H_Check": "Check", "R_H_Status": "Status", "R_H_Detail": "Detail",
        "R_Footer": "Generated by ahv_backup_restore.py v{3} (MIT license). Related files: {0}, {1}, log {2}.",
        "R_OkWarn": "OK (warnings)",
    },
    "fr": {
        "Step0": "Étape 0 - Pré-vol : connexions et contrôle de l'environnement",
        "Step1": "Étape 1 - Restauration de {0} VM vers le sous-réseau isolé",
        "Step2": "Étape 2 - Vérification des VM restaurées",
        "Step4": "Étape 4 - Rapport",
        "CP00": "Authentification VBR / plug-in AHV / Prism Central",
        "CP01": "Cluster, conteneur de stockage et sous-réseau isolé présents",
        "CP02": "Sous-réseau isolé non routé",
        "CP03": "Aucune VM hors périmètre sur le sous-réseau isolé",
        "CP04": "Aucune VM de test résiduelle",
        "CP10": "Point de restauration trouvé",
        "CP11": "Âge du point de restauration <= {0} h",
        "CP12": "Session de restauration terminée",
        "CP12Start": "Restauration lancée",
        "CP13": "Durée de restauration <= {0} min",
        "CP20": "VM démarrée",
        "CP21": "Cartes réseau sur le sous-réseau isolé uniquement",
        "CP22": "Adresse IP remontée (Nutanix Guest Tools)",
        "CP23": "Ping depuis la sonde",
        "CP30": "Contrôles applicatifs",
        "CP30Item": "Applicatif : {0}",
        "CP40": "VM de test supprimée",
        "PostRestore": "Contrôle post-restauration",
        "Verify": "Vérification",
        "D_Mode13": "plug-in intégré VBR 13.x ({0})",
        "D_Mode12": "appliance 12.x {0} ({1})",
        "D_ClusterUnknown": "cluster '{0}' inconnu du plug-in AHV",
        "D_SubnetMissing": "sous-réseau '{0}' introuvable - le créer dans Prism (VLAN non routé) puis relancer un rescan du serveur Nutanix dans Veeam",
        "D_ContainerMissing": "conteneur de stockage '{0}' introuvable",
        "D_SubnetNotInPrism": "sous-réseau introuvable dans Prism Central",
        "D_SubnetRouted": "is_external={0}, passerelle={1} - risque d'exposition des VM restaurées",
        "D_SubnetOk": "is_external=false, aucune passerelle",
        "D_ForeignVms": "VM présentes : {0}",
        "D_LeftoverDeleteFailed": "suppression impossible : {0}",
        "D_LeftoverDeleted": "{0} VM résiduelle(s) supprimée(s) : {1}",
        "D_LeftoverFound": "{0} VM résiduelle(s) - relancer avec --cleanup : {1}",
        "D_NoRestorePoint": "aucun point de restauration Nutanix AHV pour ce nom",
        "D_NoRestorePointShort": "pas de point de restauration",
        "D_CreatedOn": "créé le {0}",
        "D_RpoMissed": " - RPO non tenu, vérifier le job de sauvegarde",
        "D_SessionStarted": "    -> session {0} démarrée",
        "D_LaunchFailed": "échec au lancement",
        "D_SessionFailed": "statut = {0} après {1} min (voir la session dans la console Veeam)",
        "D_RestoreFailed": "restauration en échec",
        "D_RtoMissed": " - RTO cible dépassé",
        "D_VmNotFound": "VM '{0}' introuvable dans Prism",
        "D_VmNotFoundShort": "VM introuvable",
        "D_PowerState": "power_state = {0}",
        "D_NicLeak": "carte réseau hors sous-réseau isolé - arrêt immédiat de la VM",
        "D_NoNic": "aucune carte réseau attachée",
        "D_NoIp": "aucune IP - NGT absent, pas de DHCP sur le sous-réseau isolé ou OS non démarré",
        "D_NoIpShort": "pas d'adresse IP",
        "D_PingOff": "option --ping-check non activée",
        "D_NoChecks": "aucun contrôle défini (section AppChecks)",
        "D_CleanupOff": "option --cleanup non activée (VM conservée pour analyse)",
        "D_CleanupFailed": "{0} - supprimer manuellement '{1}' dans Prism",
        "D_Unexpected": "erreur inattendue : {0}",
        "D_DryRun": "dry-run",
        "D_ModuleMissing": "module python '{0}' absent",
        "M_NeedVm": "Indiquez au moins une VM avec -v/--vm (ou utilisez --init-config pour créer la configuration).",
        "M_ConfigWritten": "Modèle de configuration écrit dans {0}. Renseignez-le puis relancez avec -v.",
        "M_ConfigExists": "Le fichier {0} existe - utilisez --force pour l'écraser.",
        "M_ConfigUnreadable": "Configuration illisible ({0}) : {1}",
        "M_NoConfig": "Aucun fichier de configuration ({0}) : valeurs par défaut utilisées. Générez-en un avec --init-config.",
        "M_CredVbr": "Compte Veeam Backup & Replication pour {0}",
        "M_CredAhv": "Compte appliance Veeam Plug-in for Nutanix AHV pour {0}",
        "M_CredPrism": "Compte Prism Central pour {0}",
        "M_PreflightAbort": "Arrêt en pré-vol : corrigez les points KO ci-dessus puis relancez.",
        "M_Fatal": "Erreur bloquante : {0}",
        "M_ReportFailed": "Génération des rapports en échec : {0}",
        "M_Failures": "{0} point(s) de contrôle en échec.",
        "M_AllOk": "Tous les points de contrôle sont passés : les points de restauration vérifiés démarrent et répondent.",
        "M_ShutdownFailed": "Arrêt de sécurité de {0} impossible : {1}",
        "M_ApiFailed": "Appel {0} {1} en échec (HTTP {2}){3}. {4}",
        "M_Http401": " : identifiants invalides ou jeton expiré",
        "M_Http403": " : droits insuffisants pour cette opération",
        "M_Http404": " : ressource introuvable (vérifier la version d'API et les identifiants d'objets)",
        "M_Retry": "Tentative {0} échouée ({1}) - nouvelle tentative dans {2} s",
        "M_DeleteAction": "Arrêt et suppression de la VM de test {0}",
        "M_RestoreAction": "Restauration de {0} vers {1} sur {2}",
        "R_Title": "Recovery Verification - Nutanix AHV",
        "R_Run": "Exécution", "R_Cluster": "Cluster", "R_Subnet": "Sous-réseau isolé",
        "R_Fail": "ÉCHEC - {0} point(s) de contrôle KO", "R_Warn": "SUCCÈS AVEC AVERTISSEMENTS - {0} WARN", "R_Ok": "SUCCÈS - tous les points de contrôle sont passés",
        "R_KpiVms": "VM vérifiées", "R_KpiOk": "contrôles OK", "R_KpiWarn": "avertissements", "R_KpiKo": "échecs",
        "R_KpiRpo": "RPO cible", "R_KpiRto": "RTO cible",
        "R_Summary": "Synthèse par VM", "R_Details": "Détail des points de contrôle",
        "R_H_Vm": "VM", "R_H_Age": "Âge du point de restauration (h)", "R_H_Dur": "Durée de restauration (min)", "R_H_Ip": "IP",
        "R_H_Result": "Résultat", "R_H_Time": "Heure", "R_H_Check": "Contrôle", "R_H_Status": "Statut", "R_H_Detail": "Détail",
        "R_Footer": "Généré par ahv_backup_restore.py v{3} (licence MIT). Fichiers associés : {0}, {1}, journal {2}.",
        "R_OkWarn": "OK (avertissements)",
    },
}

LANG = "en"


def L(key: str, *params: Any) -> str:
    s = STRINGS[LANG].get(key, key)
    return s.format(*params) if params else s


# =====================================================================================
# Configuration
# =====================================================================================

DEFAULT_CONFIG: Dict[str, Any] = {
    "Veeam": {
        "VbrServer": "vbr.example.local",        # Veeam Backup & Replication server
        "VbrPort": 9419,                          # VBR REST API port
        "VbrApiVersion": "1.3-rev2",              # x-api-version: 1.3-rev2 = VBR 13.1, 1.3-rev1 = 13.0, 1.2-rev0 = 12.x
        "AhvIntegrated": True,                    # true = VBR 13.x (plug-in integrated, workers) | false = 12.x appliance
        "AhvAppliance": "veeam-ahv.example.local",  # 12.x only: standalone Veeam Plug-in for Nutanix AHV appliance
        "AhvApiVersion": "v9",                    # plug-in API version: v9 = 13.x integrated, v8 = 12.x appliance
    },
    "Nutanix": {
        "PrismCentral": "prism.example.local",
        "PrismPort": 9440,
    },
    "Target": {
        "ClusterName": "CLUSTER-01",                    # AHV cluster used for the restore
        "IsolatedNetworkName": "VLAN-RecoveryVerification",   # isolated, non-routed subnet
        "StorageContainerName": "default-container",
        "VmNamePrefix": "RV-",                          # prefix of test VMs
    },
    "Thresholds": {
        "MaxRestorePointAgeHours": 30,   # RPO target
        "MaxRestoreMinutes": 45,         # RTO target (13.x: include worker start-up)
        "BootTimeoutMinutes": 15,        # max wait for boot / IP
        "PollIntervalSeconds": 20,
    },
    # Application checks per VM. "*" applies to every VM. Run from the probe against the NGT IP.
    # Tcp (Port) | Http (Url with {ip}, ExpectedStatus) | Ldap (Port, needs ldap3) | Dns (Name, needs dnspython) | Sql (Port, Query, User, Password, needs pymssql)
    "AppChecks": {
        "*": [{"Type": "Tcp", "Port": 3389, "Label": "RDP (Windows)"}],
        "SRV-AD01": [{"Type": "Ldap", "Port": 389, "Label": "LDAP"}, {"Type": "Dns", "Name": "example.local", "Label": "DNS zone"}],
        "SRV-WEB01": [{"Type": "Http", "Url": "https://{ip}/health", "ExpectedStatus": 200, "Label": "Health"}],
        "SRV-SQL01": [{"Type": "Sql", "Port": 1433, "Query": "SELECT COUNT(*) FROM sys.databases WHERE state_desc='ONLINE'", "User": "rv_check", "Password": "", "Label": "Online databases"}],
    },
}

CLI_OVERRIDES = {
    "vbr_server": ("Veeam", "VbrServer"), "vbr_port": ("Veeam", "VbrPort"), "vbr_api_version": ("Veeam", "VbrApiVersion"),
    "ahv_integrated": ("Veeam", "AhvIntegrated"), "ahv_appliance": ("Veeam", "AhvAppliance"), "ahv_api_version": ("Veeam", "AhvApiVersion"),
    "prism_central": ("Nutanix", "PrismCentral"), "prism_port": ("Nutanix", "PrismPort"),
    "cluster_name": ("Target", "ClusterName"), "isolated_network_name": ("Target", "IsolatedNetworkName"),
    "storage_container_name": ("Target", "StorageContainerName"), "vm_name_prefix": ("Target", "VmNamePrefix"),
    "max_restore_point_age_hours": ("Thresholds", "MaxRestorePointAgeHours"), "max_restore_minutes": ("Thresholds", "MaxRestoreMinutes"),
    "boot_timeout_minutes": ("Thresholds", "BootTimeoutMinutes"),
}


def merge_config(path: Path, args: argparse.Namespace) -> Dict[str, Any]:
    cfg = json.loads(json.dumps(DEFAULT_CONFIG))
    if path.exists():
        try:
            file_cfg = json.loads(path.read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            raise SystemExit(L("M_ConfigUnreadable", path, e))
        for section, values in file_cfg.items():
            if section == "AppChecks" or not isinstance(values, dict):
                cfg[section] = values
            else:
                cfg.setdefault(section, {}).update(values)
        logging.debug("configuration loaded from %s", path)
    else:
        logging.warning(L("M_NoConfig", path))
    for dest, (section, key) in CLI_OVERRIDES.items():
        val = getattr(args, dest, None)
        if val is not None:
            cfg[section][key] = val
    return cfg


# =====================================================================================
# Checkpoints and logging
# =====================================================================================

COLORS = {"OK": "\033[32m", "KO": "\033[31m", "WARN": "\033[33m", "SKIP": "\033[90m", "reset": "\033[0m", "step": "\033[36m"}


class Run:
    def __init__(self, report_dir: Path, fail_on_warning: bool):
        self.run_id = datetime.now().strftime("%Y%m%d-%H%M%S")
        self.report_dir = report_dir
        self.fail_on_warning = fail_on_warning
        self.checkpoints: List[Dict[str, Any]] = []
        self.color = sys.stdout.isatty() and platform.system() != "Windows"
        report_dir.mkdir(parents=True, exist_ok=True)
        self.log_path = report_dir / f"RecoveryVerification-{self.run_id}.log"
        logging.basicConfig(level=logging.DEBUG, format="%(asctime)s %(levelname)s %(message)s",
                            handlers=[logging.FileHandler(self.log_path, encoding="utf-8")])

    def step(self, title: str) -> None:
        c, r = (COLORS["step"], COLORS["reset"]) if self.color else ("", "")
        print(f"\n{c}=== {title} ==={r}")
        logging.info("=== %s ===", title)

    def cp(self, cp_id: str, vm: str, label: str, status: str, detail: str = "", value: Optional[float] = None) -> None:
        self.checkpoints.append({"RunId": self.run_id, "Time": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"), "CP": cp_id, "VM": vm,
                                 "Label": label, "Status": status, "Value": value, "Detail": detail})
        c, r = (COLORS.get(status, ""), COLORS["reset"]) if self.color else ("", "")
        suffix = f" - {detail}" if detail else ""
        print(f"  {c}[{cp_id}] {status:<4} {vm:<16} {label}{suffix}{r}")
        logging.info("[%s] %s %s %s%s", cp_id, status, vm, label, suffix)

    def skip_remaining(self, vm: str, reason: str) -> None:
        for cp_id in ("CP13", "CP20", "CP21", "CP22", "CP23", "CP30", "CP40"):
            self.cp(cp_id, vm, L("PostRestore"), "SKIP", reason)


class Preflight(Exception):
    pass


# =====================================================================================
# HTTP / API clients
# =====================================================================================

class ApiError(Exception):
    def __init__(self, status: Optional[int], message: str):
        super().__init__(message)
        self.status = status


class Http:
    def __init__(self, verify_tls: bool):
        self.ctx = ssl.create_default_context()
        if not verify_tls:
            self.ctx.check_hostname = False
            self.ctx.verify_mode = ssl.CERT_NONE

    def call(self, method: str, url: str, headers: Optional[Dict[str, str]] = None, body: Any = None,
             form: bool = False, retries: int = 3, timeout: int = 120) -> Any:
        headers = dict(headers or {})
        data: Optional[bytes] = None
        if body is not None:
            if form:
                data = urllib.parse.urlencode(body).encode(); headers["Content-Type"] = "application/x-www-form-urlencoded"
            else:
                data = json.dumps(body).encode(); headers["Content-Type"] = "application/json"
        attempt = 0
        while True:
            attempt += 1
            req = urllib.request.Request(url, data=data, method=method, headers=headers)
            logging.debug("%s %s", method, url)
            try:
                with urllib.request.urlopen(req, context=self.ctx, timeout=timeout) as resp:
                    raw = resp.read()
                    return json.loads(raw) if raw.strip() else None
            except urllib.error.HTTPError as e:
                status, content = e.code, e.read().decode(errors="replace")[:500]
            except (urllib.error.URLError, socket.timeout, ConnectionError, OSError) as e:
                status, content = None, str(e)
            if (status is None or status >= 500 or status == 429) and attempt < retries:
                logging.debug(L("M_Retry", attempt, status, 5 * attempt)); time.sleep(5 * attempt); continue
            hint = {401: L("M_Http401"), 403: L("M_Http403"), 404: L("M_Http404")}.get(status or 0, "")
            raise ApiError(status, L("M_ApiFailed", method, url, status, hint, content).strip())


def items(resp: Any) -> List[Any]:
    if isinstance(resp, dict):
        for key in ("results", "data", "entities"):
            if key in resp:
                return list(resp[key] or [])
    return list(resp or []) if isinstance(resp, list) else []


class Vbr:
    def __init__(self, http: Http, server: str, port: int, api_version: str, user: str, password: str):
        self.http, self.server = http, server
        self.base = f"https://{server}:{port}/api/v1"
        tok = http.call("POST", f"https://{server}:{port}/api/oauth2/token", {"x-api-version": api_version},
                        {"grant_type": "password", "username": user, "password": password}, form=True, retries=1, timeout=60)
        self.token = tok["access_token"]
        self.headers = {"Authorization": f"Bearer {self.token}", "x-api-version": api_version}

    def get(self, path: str, **kw: Any) -> Any:
        return self.http.call("GET", self.base + path, self.headers, **kw)

    def latest_restore_point(self, vm_name: str) -> Optional[Dict[str, Any]]:
        name = urllib.parse.quote(vm_name)
        try:    # [API] VBR 13 (1.3-revN)
            rps = items(self.get(f"/restorePoints?nameFilter={name}&platformNameFilter=Nutanix&orderColumn=CreationTime&orderAsc=false&limit=10"))
        except ApiError:   # [API] VBR 12 (1.2-revN)
            rps = items(self.get(f"/objectRestorePoints?nameFilter={name}&platformNameFilter=NutanixAhv&orderColumn=CreationTime&orderAsc=false&limit=10"))
        rps = [r for r in rps if r.get("name") == vm_name]
        rps.sort(key=lambda r: r.get("creationTime", ""), reverse=True)
        return rps[0] if rps else None


class Ahv:
    """Veeam Plug-in for Nutanix AHV REST API - integrated (13.x, VBR token) or standalone appliance (12.x)."""

    def __init__(self, http: Http, cfg: Dict[str, Any], vbr: Vbr, appliance_user: str = "", appliance_password: str = ""):
        self.http = http
        v = cfg["Veeam"]
        if bool(v["AhvIntegrated"]):
            self.base = f"https://{v['VbrServer']}/extension/{AHV_EXTENSION_ID}/api/{v['AhvApiVersion']}"
            self.headers = {"Authorization": f"Bearer {vbr.token}"}
            self.mode = L("D_Mode13", v["AhvApiVersion"])
        else:
            tok = http.call("POST", f"https://{v['AhvAppliance']}/api/oauth2/token", None,
                            {"grant_type": "password", "username": appliance_user, "password": appliance_password}, form=True, retries=1, timeout=60)
            self.base = f"https://{v['AhvAppliance']}/api/{v['AhvApiVersion']}"
            self.headers = {"Authorization": f"Bearer {tok['access_token']}"}
            self.mode = L("D_Mode12", v["AhvAppliance"], v["AhvApiVersion"])
        self.clusters = items(self.get("/clusters"))   # connection test

    def get(self, path: str, **kw: Any) -> Any:
        return self.http.call("GET", self.base + path, self.headers, **kw)

    def post(self, path: str, body: Any = None, **kw: Any) -> Any:
        return self.http.call("POST", self.base + path, self.headers, body, **kw)

    def restore_point_nics(self, rp_id: str) -> List[Dict[str, Any]]:
        try:
            meta = self.get(f"/restorePoints/{rp_id}/metadata") or {}                  # [API] v9
            if meta.get("networkAdapters") is not None:
                return list(meta["networkAdapters"])
        except ApiError as e:
            logging.debug("metadata endpoint unavailable (%s), falling back to /networkAdapters", e.status)
        return items(self.get(f"/restorePoints/{rp_id}/networkAdapters"))               # [API] v8, deprecated in v9

    def start_isolated_restore(self, rp: Dict[str, Any], cluster: Dict[str, Any], container: Dict[str, Any], network: Dict[str, Any],
                               target_name: str, reason: str) -> Dict[str, Any]:
        nics = self.restore_point_nics(rp["id"])
        nic_map = [{"value": {"networkId": network["id"], "ipAddresses": [], "macAddress": n.get("macAddress")}} for n in nics]
        body = {"restorePointId": rp["id"], "restoreToOriginal": False, "targetVmClusterId": cluster["id"], "targetVmName": target_name,
                "storageContainerId": container["id"], "networkAdapters": nic_map, "powerOnVmAfterRestore": True,
                "restoreVmCategories": False, "reason": reason}
        resp = self.post("/restorePoints/restore", body)
        return {"SessionId": resp["sessionId"], "NicCount": len(nic_map)}

    def wait_session(self, session_id: str, timeout_min: int, poll_s: int) -> str:
        pending = {"Running", "InProgress", "None", "Pending", None}
        deadline = time.time() + timeout_min * 60
        status = None
        while True:
            time.sleep(poll_s)
            s = self.get(f"/sessions/{session_id}")
            status = s.get("result") or s.get("status")                                  # [API]
            if status not in pending or time.time() >= deadline:
                break
        return "Timeout" if status in pending else str(status)


class Prism:
    def __init__(self, http: Http, host: str, port: int, user: str, password: str):
        self.http = http
        self.base = f"https://{host}:{port}/api/nutanix/v3"
        auth = base64.b64encode(f"{user}:{password}".encode()).decode()
        self.headers = {"Authorization": f"Basic {auth}"}
        self.post("/clusters/list", {"kind": "cluster"}, retries=1, timeout=60)   # connection test

    def get(self, path: str, **kw: Any) -> Any:
        return self.http.call("GET", self.base + path, self.headers, **kw)

    def post(self, path: str, body: Any = None, **kw: Any) -> Any:
        return self.http.call("POST", self.base + path, self.headers, body or {}, **kw)

    def put(self, path: str, body: Any) -> Any:
        return self.http.call("PUT", self.base + path, self.headers, body)

    def delete(self, path: str) -> Any:
        return self.http.call("DELETE", self.base + path, self.headers)

    def subnet(self, name: str) -> Optional[Dict[str, Any]]:
        for s in items(self.post("/subnets/list", {"kind": "subnet", "filter": f"name=={name}"})):
            if (s.get("status") or {}).get("name") == name:
                return s
        return None

    def vms(self, length: int = 500) -> List[Dict[str, Any]]:
        return items(self.post("/vms/list", {"kind": "vm", "length": length}))

    def vm_by_name(self, name: str) -> Optional[Dict[str, Any]]:
        for v in items(self.post("/vms/list", {"kind": "vm", "filter": f"vm_name=={name}"})):
            if (v.get("status") or {}).get("name") == name:
                return v
        return None

    def set_power(self, uuid: str, state: str) -> None:
        cur = self.get(f"/vms/{uuid}")
        if ((cur.get("status") or {}).get("resources") or {}).get("power_state") == state:
            return
        spec = {"metadata": cur["metadata"], "spec": cur["spec"]}
        spec["spec"]["resources"]["power_state"] = state
        self.put(f"/vms/{uuid}", spec)

    def remove_vm(self, uuid: str) -> None:
        self.set_power(uuid, "OFF")
        time.sleep(20)
        self.delete(f"/vms/{uuid}")


def vm_name(v: Dict[str, Any]) -> str:
    return str((v.get("status") or {}).get("name", ""))


def vm_nic_subnets(v: Dict[str, Any]) -> List[str]:
    return [str((n.get("subnet_reference") or {}).get("uuid")) for n in ((v.get("status") or {}).get("resources") or {}).get("nic_list", [])]


def vm_ip(v: Dict[str, Any]) -> Optional[str]:
    for n in ((v.get("status") or {}).get("resources") or {}).get("nic_list", []):
        for ep in n.get("ip_endpoint_list", []):
            if ep.get("ip"):
                return str(ep["ip"])
    return None


# =====================================================================================
# Application checks (from the probe)
# =====================================================================================

def app_check(check: Dict[str, Any], ip: str) -> Dict[str, Any]:
    t = check.get("Type")
    try:
        if t == "Tcp":
            with socket.create_connection((ip, int(check["Port"])), timeout=5):
                return {"Ok": True, "Detail": f"tcp/{check['Port']}"}
        if t == "Http":
            url = check["Url"].replace("{ip}", ip)
            ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
            try:
                with urllib.request.urlopen(urllib.request.Request(url), context=ctx, timeout=15) as resp:
                    code = resp.status
            except urllib.error.HTTPError as e:
                code = e.code
            return {"Ok": code == int(check.get("ExpectedStatus", 200)), "Detail": f"HTTP {code} {url}"}
        if t == "Ldap":
            try:
                import ldap3  # type: ignore
            except ImportError:
                return {"Ok": None, "Detail": L("D_ModuleMissing", "ldap3")}
            conn = ldap3.Connection(ldap3.Server(ip, port=int(check.get("Port", 389)), connect_timeout=5), auto_bind=True)
            conn.unbind()
            return {"Ok": True, "Detail": "anonymous RootDSE bind OK"}
        if t == "Dns":
            try:
                import dns.resolver  # type: ignore
            except ImportError:
                return {"Ok": None, "Detail": L("D_ModuleMissing", "dnspython")}
            res = dns.resolver.Resolver(configure=False); res.nameservers = [ip]; res.lifetime = 5
            ans = res.resolve(check["Name"], check.get("RecordType", "A"))
            return {"Ok": len(ans) > 0, "Detail": f"{check['Name']} -> {ip}"}
        if t == "Sql":
            try:
                import pymssql  # type: ignore
            except ImportError:
                return {"Ok": None, "Detail": L("D_ModuleMissing", "pymssql")}
            conn = pymssql.connect(server=ip, port=int(check.get("Port", 1433)), user=check.get("User"), password=check.get("Password"), login_timeout=15)
            cur = conn.cursor(); cur.execute(check["Query"]); row = cur.fetchone(); conn.close()
            return {"Ok": row is not None, "Detail": f"result = {row[0] if row else None}"}
        return {"Ok": None, "Detail": f"unknown check type: {t}"}
    except Exception as e:  # noqa: BLE001
        return {"Ok": False, "Detail": str(e)[:200]}


def checks_for(cfg: Dict[str, Any], vm: str) -> List[Dict[str, Any]]:
    ac = cfg.get("AppChecks") or {}
    return list(ac.get("*", [])) + list(ac.get(vm, []))


def ping(ip: str) -> bool:
    cmd = ["ping", "-n", "2", "-w", "2000", ip] if platform.system() == "Windows" else ["ping", "-c", "2", "-W", "2", ip]
    return subprocess.run(cmd, capture_output=True).returncode == 0


# =====================================================================================
# Reports
# =====================================================================================

def summary(vm_names: List[str], cps: List[Dict[str, Any]], fail_on_warning: bool) -> List[Dict[str, Any]]:
    rows = []
    for vm in vm_names:
        mine = [c for c in cps if c["VM"] == vm]
        ko = sum(1 for c in mine if c["Status"] == "KO"); wa = sum(1 for c in mine if c["Status"] == "WARN")
        first = lambda cp_id, ok_only=False: next((c for c in mine if c["CP"] == cp_id and (not ok_only or c["Status"] == "OK")), None)  # noqa: E731
        c11, c13, c22 = first("CP11"), first("CP13"), first("CP22", True)
        rows.append({"VM": vm, "RestorePointAgeH": c11["Value"] if c11 else None, "RestoreMinutes": c13["Value"] if c13 else None,
                     "IP": c22["Detail"] if c22 else "", "KO": ko, "WARN": wa,
                     "Result": "KO" if ko or (fail_on_warning and wa) else (L("R_OkWarn") if wa else "OK")})
    return rows


def export_reports(run: Run, cfg: Dict[str, Any], vm_names: List[str], rows: List[Dict[str, Any]]) -> Dict[str, Path]:
    d, rid = run.report_dir, run.run_id
    csv_p, json_p, html_p = d / f"RecoveryVerification-{rid}.csv", d / f"RecoveryVerification-{rid}.json", d / f"RecoveryVerification-{rid}.html"
    with csv_p.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["RunId", "Time", "CP", "VM", "Label", "Status", "Value", "Detail"], delimiter=";")
        w.writeheader(); w.writerows(run.checkpoints)
    json_p.write_text(json.dumps({"RunId": rid, "Date": datetime.now().isoformat(timespec="seconds"), "Language": LANG, "Platform": "NutanixAHV",
                                  "Method": "FullRestoreToIsolatedSubnet", "Version": VERSION, "Target": cfg["Target"], "Thresholds": cfg["Thresholds"],
                                  "Summary": rows, "Checkpoints": run.checkpoints}, indent=2, ensure_ascii=False), encoding="utf-8")
    tot = {s: sum(1 for c in run.checkpoints if c["Status"] == s) for s in ("OK", "KO", "WARN")}
    banner = (L("R_Fail", tot["KO"]), "#c62828") if tot["KO"] else ((L("R_Warn", tot["WARN"]), "#ef6c00") if tot["WARN"] else (L("R_Ok"), "#2e7d32"))
    e = lambda x: html.escape("" if x is None else str(x))  # noqa: E731
    ok_warn = L("R_OkWarn")
    rows_html = "\n".join(
        f"<tr><td>{e(r['VM'])}</td><td>{e(r['RestorePointAgeH'])}</td><td>{e(r['RestoreMinutes'])}</td><td>{e(r['IP'])}</td><td>{r['KO']}</td><td>{r['WARN']}</td>"
        f"<td class='{'ko' if r['Result'] == 'KO' else ('warn' if r['Result'] == ok_warn else 'ok')}'>{e(r['Result'])}</td></tr>" for r in rows)
    cps_html = "\n".join(
        f"<tr><td>{e(c['Time'])}</td><td>{e(c['CP'])}</td><td>{e(c['VM'])}</td><td>{e(c['Label'])}</td><td class='{c['Status'].lower()}'>{e(c['Status'])}</td><td>{e(c['Detail'])}</td></tr>"
        for c in run.checkpoints)
    th = cfg["Thresholds"]
    html_p.write_text(f"""<!DOCTYPE html><html lang="{LANG}"><head><meta charset="utf-8"><title>{e(L('R_Title'))} - {rid}</title>
<style>
body{{font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#222;margin:24px;background:#fafafa}}
h1{{font-size:20px;margin:0 0 4px}}h2{{font-size:16px;margin:24px 0 8px;border-bottom:1px solid #ddd;padding-bottom:4px}}
.banner{{color:#fff;padding:10px 14px;border-radius:4px;font-weight:600;margin:12px 0;background:{banner[1]}}}
.kpi{{display:inline-block;background:#fff;border:1px solid #e0e0e0;border-radius:4px;padding:8px 14px;margin:0 8px 8px 0}}.kpi b{{font-size:18px;display:block}}
table{{border-collapse:collapse;width:100%;background:#fff}}th,td{{border:1px solid #e0e0e0;padding:6px 8px;text-align:left;vertical-align:top}}
th{{background:#f0f0f0}}td.ok{{background:#e8f5e9;color:#2e7d32;font-weight:600}}td.ko{{background:#ffebee;color:#c62828;font-weight:600}}
td.warn{{background:#fff3e0;color:#ef6c00;font-weight:600}}td.skip{{color:#888}}small{{color:#666}}
</style></head><body>
<h1>{e(L('R_Title'))}</h1>
<small>{e(L('R_Run'))} {rid} &middot; {datetime.now():%Y-%m-%d %H:%M} &middot; {e(L('R_Cluster'))} {e(cfg['Target']['ClusterName'])} &middot; {e(L('R_Subnet'))} {e(cfg['Target']['IsolatedNetworkName'])} &middot; VBR {e(cfg['Veeam']['VbrServer'])}</small>
<div class="banner">{e(banner[0])}</div>
<div class="kpi"><b>{len(vm_names)}</b>{e(L('R_KpiVms'))}</div><div class="kpi"><b>{tot['OK']}</b>{e(L('R_KpiOk'))}</div>
<div class="kpi"><b>{tot['WARN']}</b>{e(L('R_KpiWarn'))}</div><div class="kpi"><b>{tot['KO']}</b>{e(L('R_KpiKo'))}</div>
<div class="kpi"><b>{th['MaxRestorePointAgeHours']} h</b>{e(L('R_KpiRpo'))}</div><div class="kpi"><b>{th['MaxRestoreMinutes']} min</b>{e(L('R_KpiRto'))}</div>
<h2>{e(L('R_Summary'))}</h2>
<table><tr><th>{e(L('R_H_Vm'))}</th><th>{e(L('R_H_Age'))}</th><th>{e(L('R_H_Dur'))}</th><th>{e(L('R_H_Ip'))}</th><th>KO</th><th>WARN</th><th>{e(L('R_H_Result'))}</th></tr>
{rows_html}</table>
<h2>{e(L('R_Details'))}</h2>
<table><tr><th>{e(L('R_H_Time'))}</th><th>CP</th><th>{e(L('R_H_Vm'))}</th><th>{e(L('R_H_Check'))}</th><th>{e(L('R_H_Status'))}</th><th>{e(L('R_H_Detail'))}</th></tr>
{cps_html}</table>
<p><small>{e(L('R_Footer', csv_p.name, json_p.name, run.log_path.name, VERSION))}</small></p>
</body></html>
""", encoding="utf-8")
    return {"Csv": csv_p, "Json": json_p, "Html": html_p}


# =====================================================================================
# Secrets
# =====================================================================================

def load_secrets(args: argparse.Namespace, cfg: Dict[str, Any]) -> Dict[str, str]:
    s: Dict[str, str] = {}
    if args.secrets_file:
        p = Path(args.secrets_file)
        if platform.system() != "Windows" and p.stat().st_mode & 0o077:
            logging.warning("secrets file %s is readable by others (chmod 600 recommended)", p)
        s.update(json.loads(p.read_text(encoding="utf-8")))
    for k in ("VBR_USER", "VBR_PASSWORD", "PRISM_USER", "PRISM_PASSWORD", "AHV_USER", "AHV_PASSWORD"):
        if os.environ.get(k):
            s[k] = os.environ[k]

    def ask(user_key: str, pass_key: str, prompt: str) -> None:
        if not s.get(user_key) or not s.get(pass_key):
            print(prompt)
            s[user_key] = s.get(user_key) or input("  user: ")
            s[pass_key] = s.get(pass_key) or getpass.getpass("  password: ")

    ask("VBR_USER", "VBR_PASSWORD", L("M_CredVbr", cfg["Veeam"]["VbrServer"]))
    if not bool(cfg["Veeam"]["AhvIntegrated"]):
        ask("AHV_USER", "AHV_PASSWORD", L("M_CredAhv", cfg["Veeam"]["AhvAppliance"]))
    ask("PRISM_USER", "PRISM_PASSWORD", L("M_CredPrism", cfg["Nutanix"]["PrismCentral"]))
    return s


# =====================================================================================
# Main
# =====================================================================================

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="ahv_backup_restore.py", description=__doc__.split("\n\n")[0], formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("-v", "--vm", dest="vm_names", action="append", metavar="NAME", help="source VM name as shown in Veeam (repeatable)")
    p.add_argument("-c", "--config", default="./RecoveryVerification.json", help="JSON configuration file (default ./RecoveryVerification.json)")
    p.add_argument("--init-config", action="store_true", help="write a configuration template to --config and exit")
    p.add_argument("--force", action="store_true", help="overwrite an existing configuration with --init-config")
    p.add_argument("-l", "--language", choices=["en", "fr"], help="output language (default: system locale)")
    p.add_argument("--ping-check", action="store_true", help="enable CP23 (ping the restored VM from this machine)")
    p.add_argument("--cleanup", action="store_true", help="delete test VMs at the end (and leftovers from previous runs)")
    p.add_argument("--fail-on-warning", action="store_true", help="treat WARN as failure for the exit code")
    p.add_argument("--report-dir", default="./Reports", help="output folder for reports and log (default ./Reports)")
    p.add_argument("--secrets-file", help="JSON file with VBR_USER, VBR_PASSWORD, PRISM_USER, PRISM_PASSWORD [, AHV_USER, AHV_PASSWORD] (chmod 600)")
    p.add_argument("--verify-tls", action="store_true", help="validate TLS certificates (default: skip, self-signed)")
    p.add_argument("-n", "--dry-run", action="store_true", help="pre-flight only; restore / delete are displayed, not executed")
    p.add_argument("--debug", action="store_true", help="also print debug log to the console")
    g = p.add_argument_group("configuration overrides")
    g.add_argument("--vbr-server"); g.add_argument("--vbr-port", type=int); g.add_argument("--vbr-api-version")
    g.add_argument("--ahv-integrated", type=lambda x: x.lower() in ("1", "true", "yes"), metavar="true|false")
    g.add_argument("--ahv-appliance"); g.add_argument("--ahv-api-version")
    g.add_argument("--prism-central"); g.add_argument("--prism-port", type=int)
    g.add_argument("--cluster-name"); g.add_argument("--isolated-network-name"); g.add_argument("--storage-container-name"); g.add_argument("--vm-name-prefix")
    g.add_argument("--max-restore-point-age-hours", type=int); g.add_argument("--max-restore-minutes", type=int); g.add_argument("--boot-timeout-minutes", type=int)
    p.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    return p


def main() -> int:  # noqa: C901 - orchestration
    global LANG
    args = build_parser().parse_args()
    LANG = args.language or ("fr" if (locale.getlocale()[0] or os.environ.get("LANG", "")).lower().startswith("fr") else "en")
    cfg_path = Path(args.config)

    if args.init_config:
        if cfg_path.exists() and not args.force:
            print(L("M_ConfigExists", cfg_path)); return 2
        cfg_path.write_text(json.dumps(DEFAULT_CONFIG, indent=2, ensure_ascii=False), encoding="utf-8")
        print(L("M_ConfigWritten", cfg_path)); return 0
    if not args.vm_names:
        print(L("M_NeedVm")); return 2

    run = Run(Path(args.report_dir), args.fail_on_warning)
    if args.debug:
        logging.getLogger().addHandler(logging.StreamHandler(sys.stderr))
    cfg = merge_config(cfg_path, args)
    secrets = load_secrets(args, cfg)
    http = Http(args.verify_tls)
    prefix, poll = cfg["Target"]["VmNamePrefix"], int(cfg["Thresholds"]["PollIntervalSeconds"])
    th = cfg["Thresholds"]
    exit_code = 0
    sessions: Dict[str, Dict[str, Any]] = {}

    try:
        # ------------------------------------------------------------------ Step 0
        run.step(L("Step0"))
        try:
            vbr = Vbr(http, cfg["Veeam"]["VbrServer"], int(cfg["Veeam"]["VbrPort"]), cfg["Veeam"]["VbrApiVersion"], secrets["VBR_USER"], secrets["VBR_PASSWORD"])
            ahv = Ahv(http, cfg, vbr, secrets.get("AHV_USER", ""), secrets.get("AHV_PASSWORD", ""))
            prism = Prism(http, cfg["Nutanix"]["PrismCentral"], int(cfg["Nutanix"]["PrismPort"]), secrets["PRISM_USER"], secrets["PRISM_PASSWORD"])
            run.cp("CP00", "-", L("CP00"), "OK", ahv.mode)
        except Exception as e:  # noqa: BLE001
            run.cp("CP00", "-", L("CP00"), "KO", str(e)); raise Preflight()

        try:
            cluster = next((c for c in ahv.clusters if c.get("name") == cfg["Target"]["ClusterName"]), None)
            if not cluster:
                raise RuntimeError(L("D_ClusterUnknown", cfg["Target"]["ClusterName"]))
            network = next((n for n in items(ahv.get(f"/clusters/{cluster['id']}/networks")) if n.get("name") == cfg["Target"]["IsolatedNetworkName"]), None)
            if not network:
                raise RuntimeError(L("D_SubnetMissing", cfg["Target"]["IsolatedNetworkName"]))
            container = next((c for c in items(ahv.get(f"/clusters/{cluster['id']}/storageContainers")) if c.get("name") == cfg["Target"]["StorageContainerName"]), None)
            if not container:
                raise RuntimeError(L("D_ContainerMissing", cfg["Target"]["StorageContainerName"]))
            run.cp("CP01", "-", L("CP01"), "OK", f"{cluster['name']} / {container['name']} / {network['name']}")
        except Exception as e:  # noqa: BLE001
            run.cp("CP01", "-", L("CP01"), "KO", str(e)); raise Preflight()

        # CP02 - real subnet isolation (blocking)
        subnet = prism.subnet(cfg["Target"]["IsolatedNetworkName"])
        if not subnet:
            run.cp("CP02", "-", L("CP02"), "KO", L("D_SubnetNotInPrism")); raise Preflight()
        res = (subnet.get("status") or {}).get("resources") or {}
        gateway = (res.get("ip_config") or {}).get("default_gateway_ip")
        if res.get("is_external") is True or gateway:
            run.cp("CP02", "-", L("CP02"), "KO", L("D_SubnetRouted", res.get("is_external"), gateway)); raise Preflight()
        run.cp("CP02", "-", L("CP02"), "OK", L("D_SubnetOk"))
        subnet_uuid = subnet["metadata"]["uuid"]

        # CP03 / CP04 - subnet occupants and leftover test VMs
        all_vms = prism.vms()
        on_iso = [v for v in all_vms if subnet_uuid in vm_nic_subnets(v)]
        foreign = [v for v in on_iso if not vm_name(v).startswith(prefix)]
        if foreign:
            run.cp("CP03", "-", L("CP03"), "KO", L("D_ForeignVms", ", ".join(vm_name(v) for v in foreign)))
        else:
            run.cp("CP03", "-", L("CP03"), "OK")
        stale = [v for v in all_vms if vm_name(v).startswith(prefix)]
        if not stale:
            run.cp("CP04", "-", L("CP04"), "OK")
        elif args.cleanup:
            failed = []
            for sv in stale:
                try:
                    if not args.dry_run:
                        prism.remove_vm(sv["metadata"]["uuid"])
                except Exception:  # noqa: BLE001
                    failed.append(vm_name(sv))
            if failed:
                run.cp("CP04", "-", L("CP04"), "KO", L("D_LeftoverDeleteFailed", ", ".join(failed))); raise Preflight()
            run.cp("CP04", "-", L("CP04"), "WARN", L("D_LeftoverDeleted", len(stale), ", ".join(vm_name(v) for v in stale)))
        else:
            run.cp("CP04", "-", L("CP04"), "KO", L("D_LeftoverFound", len(stale), ", ".join(vm_name(v) for v in stale))); raise Preflight()

        # ------------------------------------------------------------------ Step 1
        run.step(L("Step1", len(args.vm_names)))
        for vm in args.vm_names:
            try:
                rp = vbr.latest_restore_point(vm)
                if not rp:
                    run.cp("CP10", vm, L("CP10"), "KO", L("D_NoRestorePoint")); run.skip_remaining(vm, L("D_NoRestorePointShort")); continue
                run.cp("CP10", vm, L("CP10"), "OK", L("D_CreatedOn", rp.get("creationTime")))
                created = datetime.fromisoformat(str(rp["creationTime"]).replace("Z", "+00:00"))
                if created.tzinfo is None:
                    created = created.replace(tzinfo=timezone.utc)
                age_h = round((datetime.now(timezone.utc) - created).total_seconds() / 3600, 1)
                rpo_ok = age_h <= float(th["MaxRestorePointAgeHours"])
                run.cp("CP11", vm, L("CP11", th["MaxRestorePointAgeHours"]), "OK" if rpo_ok else "KO", f"{age_h} h" + ("" if rpo_ok else L("D_RpoMissed")), age_h)

                target = f"{prefix}{vm}"
                if args.dry_run:
                    print(f"  [dry-run] {L('M_RestoreAction', vm, target, network['name'])}"); run.skip_remaining(vm, L("D_DryRun")); continue
                r = ahv.start_isolated_restore(rp, cluster, container, network, target, f"Recovery Verification {run.run_id}")
                sessions[vm] = {"SessionId": r["SessionId"], "NicCount": r["NicCount"], "Started": time.time(), "Target": target}
                print(L("D_SessionStarted", r["SessionId"]))
            except Exception as e:  # noqa: BLE001
                run.cp("CP12", vm, L("CP12Start"), "KO", str(e)[:300]); run.skip_remaining(vm, L("D_LaunchFailed"))

        # ------------------------------------------------------------------ Step 2
        run.step(L("Step2"))
        for vm, s in sessions.items():
            vm_uuid: Optional[str] = None
            try:
                status = ahv.wait_session(s["SessionId"], int(th["MaxRestoreMinutes"]) + int(th["BootTimeoutMinutes"]), poll)
                dur_min = round((time.time() - s["Started"]) / 60, 1)
                if status not in ("Success", "Warning"):
                    run.cp("CP12", vm, L("CP12"), "KO", L("D_SessionFailed", status, dur_min)); run.skip_remaining(vm, L("D_RestoreFailed")); continue
                run.cp("CP12", vm, L("CP12"), "OK" if status == "Success" else "WARN", status)
                rto_ok = dur_min <= float(th["MaxRestoreMinutes"])
                run.cp("CP13", vm, L("CP13", th["MaxRestoreMinutes"]), "OK" if rto_ok else "WARN", f"{dur_min} min" + ("" if rto_ok else L("D_RtoMissed")), dur_min)

                # CP20 / CP21 / CP22 - wait for power ON and NGT IP
                deadline = time.time() + int(th["BootTimeoutMinutes"]) * 60
                pv, ip = None, None
                while True:
                    time.sleep(poll)
                    pv = prism.vm_by_name(s["Target"])
                    ip = vm_ip(pv) if pv else None
                    if ip or time.time() >= deadline:
                        break
                if not pv:
                    run.cp("CP20", vm, L("CP20"), "KO", L("D_VmNotFound", s["Target"])); run.skip_remaining(vm, L("D_VmNotFoundShort")); continue
                vm_uuid = pv["metadata"]["uuid"]
                power = ((pv.get("status") or {}).get("resources") or {}).get("power_state")
                run.cp("CP20", vm, L("CP20"), "OK" if power == "ON" else "KO", L("D_PowerState", power))

                nic_subnets = sorted(set(vm_nic_subnets(pv)))
                leak = [u for u in nic_subnets if u != subnet_uuid]
                if leak:
                    run.cp("CP21", vm, L("CP21"), "KO", L("D_NicLeak"))
                    try:
                        prism.set_power(vm_uuid, "OFF")
                    except Exception as e:  # noqa: BLE001
                        logging.warning(L("M_ShutdownFailed", s["Target"], e))
                elif not nic_subnets and s["NicCount"] > 0:
                    run.cp("CP21", vm, L("CP21"), "WARN", L("D_NoNic"))
                else:
                    run.cp("CP21", vm, L("CP21"), "OK")

                if ip:
                    run.cp("CP22", vm, L("CP22"), "OK", ip)
                else:
                    run.cp("CP22", vm, L("CP22"), "WARN" if power == "ON" else "KO", L("D_NoIp"))

                if not args.ping_check:
                    run.cp("CP23", vm, L("CP23"), "SKIP", L("D_PingOff"))
                elif not ip:
                    run.cp("CP23", vm, L("CP23"), "SKIP", L("D_NoIpShort"))
                else:
                    run.cp("CP23", vm, L("CP23"), "OK" if ping(ip) else "KO", ip)

                checks = checks_for(cfg, vm)
                if not ip:
                    run.cp("CP30", vm, L("CP30"), "SKIP", L("D_NoIpShort"))
                elif not checks:
                    run.cp("CP30", vm, L("CP30"), "SKIP", L("D_NoChecks"))
                else:
                    for c in checks:
                        r = app_check(c, ip)
                        st = "SKIP" if r["Ok"] is None else ("OK" if r["Ok"] else "KO")
                        run.cp("CP30", vm, L("CP30Item", c.get("Label") or c.get("Type")), st, r["Detail"])
            except Exception as e:  # noqa: BLE001
                run.cp("CP20", vm, L("Verify"), "KO", L("D_Unexpected", str(e)[:300]))
            finally:
                # Step 3 - Cleanup (always attempted)
                if not args.cleanup:
                    run.cp("CP40", vm, L("CP40"), "SKIP", L("D_CleanupOff"))
                elif not vm_uuid:
                    run.cp("CP40", vm, L("CP40"), "SKIP", L("D_VmNotFoundShort"))
                else:
                    try:
                        prism.remove_vm(vm_uuid); run.cp("CP40", vm, L("CP40"), "OK", s["Target"])
                    except Exception as e:  # noqa: BLE001
                        run.cp("CP40", vm, L("CP40"), "KO", L("D_CleanupFailed", str(e)[:200], s["Target"]))
    except Preflight:
        print(f"\n{L('M_PreflightAbort')}"); exit_code = 2
    except KeyboardInterrupt:
        print("\ninterrupted"); exit_code = 2
    except Exception as e:  # noqa: BLE001
        print(f"\n{L('M_Fatal', e)}"); logging.exception("fatal"); exit_code = 2
    finally:
        # ------------------------------------------------------------------ Step 4
        run.step(L("Step4"))
        try:
            rows = summary(args.vm_names, run.checkpoints, args.fail_on_warning)
            files = export_reports(run, cfg, args.vm_names, rows)
            fmt = lambda x: "" if x is None else str(x)  # noqa: E731
            print(f"  {'VM':<20}{'Age(h)':>8}{'Restore(min)':>13}  {'IP':<16}{'KO':>4}{'WARN':>5}  Result")
            for r in rows:
                print(f"  {r['VM']:<20}{fmt(r['RestorePointAgeH']):>8}{fmt(r['RestoreMinutes']):>13}  {r['IP']:<16}{r['KO']:>4}{r['WARN']:>5}  {r['Result']}")
            print(f"\nHTML : {files['Html']}\nCSV  : {files['Csv']}\nJSON : {files['Json']}\nLog  : {run.log_path}")
        except Exception as e:  # noqa: BLE001
            print(L("M_ReportFailed", e)); logging.exception("report")
        if exit_code == 0:
            failures = sum(1 for c in run.checkpoints if c["Status"] == "KO" or (args.fail_on_warning and c["Status"] == "WARN"))
            if failures:
                print(f"\n{L('M_Failures', failures)}"); exit_code = 1
            else:
                print(f"\n{L('M_AllOk')}")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
