# Example reports — fake data / Exemples de rapports — données fictives

**EN** — Output of `ahv_backup_restore.py` v2.0.0 against a **simulated** environment (mocked Veeam and Prism APIs, VBR 13.1 integrated plug-in mode): five VMs, one restore point older than the RPO, one restore longer than the RTO, one VM without Nutanix Guest Tools, one failing HTTP check, one VM with no restore point. Every host name, IP and identifier is invented. Open the HTML files in a browser; CSV / JSON are what a SIEM or Power BI would ingest.

**FR** — Sortie de `ahv_backup_restore.py` v2.0.0 sur un environnement **simulé** (API Veeam et Prism factices, mode plug-in intégré VBR 13.1) : cinq VM, un point de restauration plus ancien que le RPO, une restauration plus longue que le RTO, une VM sans Nutanix Guest Tools, un contrôle HTTP en échec, une VM sans point de restauration. Noms d'hôtes, IP et identifiants sont inventés. Ouvrir les HTML dans un navigateur ; CSV / JSON sont ce qu'un SIEM ou Power BI ingérerait.

| | English | Français |
|---|---|---|
| HTML | [RecoveryVerification-20260919-050000.html](en/RecoveryVerification-20260919-050000.html) | [RecoveryVerification-20260919-050000.html](fr/RecoveryVerification-20260919-050000.html) |
| CSV | [RecoveryVerification-20260919-050000.csv](en/RecoveryVerification-20260919-050000.csv) | [RecoveryVerification-20260919-050000.csv](fr/RecoveryVerification-20260919-050000.csv) |
| JSON | [RecoveryVerification-20260919-050000.json](en/RecoveryVerification-20260919-050000.json) | [RecoveryVerification-20260919-050000.json](fr/RecoveryVerification-20260919-050000.json) |

Rendered preview (GitHub does not render HTML in-repo): open through https://htmlpreview.github.io/?https://github.com/CLahiani/veeam-ahv-recovery-verification/blob/main/examples/en/RecoveryVerification-20260919-050000.html
