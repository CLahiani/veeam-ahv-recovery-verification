# Register a daily Windows Scheduled Task on a Windows probe (Python 3 installed, e.g. from python.org or winget).
# Run once as administrator. Secrets file: C:\ProgramData\VeeamRV\secrets.json (restrict ACL to the service account).
$py   = (Get-Command python.exe).Source
$args = '"C:\Tools\RecoveryVerification\ahv_backup_restore.py" --config "C:\Tools\RecoveryVerification\RecoveryVerification.json" ' +
        '--secrets-file "C:\ProgramData\VeeamRV\secrets.json" --report-dir "C:\Tools\RecoveryVerification\Reports" ' +
        '--vm SRV-AD01 --vm SRV-FILE01 --ping-check --cleanup --fail-on-warning'
$action  = New-ScheduledTaskAction -Execute $py -Argument $args -WorkingDirectory 'C:\Tools\RecoveryVerification'
$trigger = New-ScheduledTaskTrigger -Daily -At 06:00
Register-ScheduledTask -TaskName 'Veeam Recovery Verification AHV' -Action $action -Trigger $trigger -User 'DOMAIN\svc-rv' -Password (Read-Host 'svc-rv password' -AsSecureString | ConvertFrom-SecureString -AsPlainText) -RunLevel Limited
