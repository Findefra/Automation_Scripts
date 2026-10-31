#!/bin/bash
# disk-hygiene.sh — aggressive but safe cleanup for Ubuntu application hosts

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

LOCKFILE="/var/run/ops-disk-hygiene.lock"
exec 200>"${LOCKFILE}"
flock -n 200 || exit 0

THRESHOLD_PCT=85
INODE_THRESHOLD=90
LOG_ROOT="/var/log"
TMP_ROOTS=("/tmp" "/var/tmp")

log INFO "Disk hygiene starting"

df -h / /var /var/log 2>/dev/null | while read -r line; do
  log INFO "df: ${line}"
done

# journald vacuum
if command -v journalctl >/dev/null; then
  journalctl --vacuum-size=500M --vacuum-time=7d 2>/dev/null || true
  log INFO "journald vacuumed"
fi

# Truncate runaway logs
find "${LOG_ROOT}" -type f -name "*.log" -size +500M -mtime +1 -print0 2>/dev/null | \
  while IFS= read -r -d '' f; do
    log WARN "Truncating large log: ${f}"
    : > "${f}"
  done

# Old rotated logs
find "${LOG_ROOT}" -type f \( -name "*.gz" -o -name "*.old" -o -name "*.1" \) -mtime +14 -delete 2>/dev/null || true

# Temporary directories
for t in "${TMP_ROOTS[@]}"; do
  find "${t}" -type f -mtime +3 -delete 2>/dev/null || true
  find "${t}" -type d -empty -mtime +1 -delete 2>/dev/null || true
done

# Old kernels (keep current + one previous) — Ubuntu style
if command -v apt-get >/dev/null; then
  # Remove old linux-image packages safely
  dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/ && $2 !~ /'$(uname -r | sed 's/-generic//')'/ {print $2}' | \
    grep -v "$(uname -r)" | head -n -1 | xargs -r apt-get -y purge 2>/dev/null || true
fi

# Inode pressure
INODE_PCT=$(df -i / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ ${INODE_PCT} -gt ${INODE_THRESHOLD} ]]; then
  log ERROR "Inode usage critical: ${INODE_PCT}%"
  find /tmp /var/tmp -type f -size -1k -mtime +1 -delete 2>/dev/null || true
fi

USE_PCT=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ ${USE_PCT} -gt ${THRESHOLD_PCT} ]]; then
  log ERROR "Root filesystem still above ${THRESHOLD_PCT}% after hygiene (${USE_PCT}%)"
  exit 1
fi

log INFO "Disk hygiene completed (root=${USE_PCT}%)"
