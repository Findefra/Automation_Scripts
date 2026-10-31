#!/bin/bash
# daily-snapshot.sh — compact daily evidence for audits and debugging

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
  echo "--- Last update ---"
  dnf history list | head -5
  echo
  echo "--- SELinux ---"
  getenforce
  echo
  echo "--- Disk ---"
  df -h /
  df -i /
  echo
  echo "--- Critical services ---"
  systemctl is-active firewalld sshd || true
  echo
  echo "--- Package hash ---"
  rpm -qa | sort | sha256sum
} > "${REPORT}"

log INFO "Daily snapshot written to ${REPORT}"

# Optional: push to S3 / Azure Blob
# aws s3 cp "${REPORT}" "s3://your-ops-bucket/snapshots/$(get_instance_id)/" ...
