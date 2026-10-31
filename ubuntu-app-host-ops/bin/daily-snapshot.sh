#!/bin/bash
# daily-snapshot.sh — compact daily evidence for audits and debugging (Ubuntu)

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

OUTDIR="/var/lib/ops/snapshots"
mkdir -p "${OUTDIR}"
STAMP=$(date -u +%Y%m%d)
REPORT="${OUTDIR}/snapshot-${STAMP}.txt"

{
  echo "=== OPS SNAPSHOT $(date -u) ==="
  echo "Instance: $(get_instance_id)"
  echo "Cloud:    $(detect_cloud)"
  echo "Region:   $(get_region)"
  echo "PrivateIP:$(get_private_ip)"
  echo
  echo "--- Kernel ---"
  uname -r
  echo
  echo "--- Last upgrades ---"
  grep -E "upgrade|install" /var/log/apt/history.log 2>/dev/null | tail -10 || true
  echo
  echo "--- AppArmor ---"
  aa-status --enabled 2>/dev/null && echo "enabled" || echo "not enabled / not installed"
  echo
  echo "--- Disk ---"
  df -h /
  df -i /
  echo
  echo "--- Critical services ---"
  systemctl is-active ssh ufw 2>/dev/null || true
  echo
  echo "--- Package hash ---"
  dpkg-query -W -f='${Package}\t${Version}\n' | sort | sha256sum
} > "${REPORT}"

log INFO "Daily snapshot written to ${REPORT}"
