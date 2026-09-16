#!/usr/bin/env bash
# Daily rotation: verify 3 different VMs each day from vms.txt (one name per line). Use as ExecStart instead of a fixed --vm list.
set -euo pipefail
cd /opt/veeam-recovery-verification
mapfile -t ALL < <(grep -v '^\s*#' vms.txt | grep -v '^\s*$')
N=${#ALL[@]}; D=$(date +%j); ARGS=()
for i in 0 1 2; do ARGS+=(--vm "${ALL[$(( (D*3 + i) % N ))]}"); done
exec /usr/bin/python3 ./ahv_backup_restore.py --config ./RecoveryVerification.json --secrets-file "$HOME/.veeam-rv-secrets.json" \
     --report-dir /var/lib/veeam-recovery-verification/reports --ping-check --cleanup "${ARGS[@]}"
