#!/bin/bash
# disk-hygiene.sh — aggressive but safe cleanup of the usual disk killers
# Runs every 15-30 min via timer. Protects application data paths.

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

# Report current state
df -h / /var /var/log 2>/dev/null | while read -r line; do
  log INFO "df: ${line}"
done

# 1. Journald size control (very common silent filler)
if command -v journalctl >/dev/null; then
  journalctl --vacuum-size=500M --vacuum-time=7d 2>/dev/null || true
  log INFO "journald vacuumed"
fi

# 2. Truncate runaway application / system logs that logrotate missed
find "${LOG_ROOT}" -type f -name "*.log" -size +500M -mtime +1 -print0 2>/dev/null | \
  while IFS= read -r -d '' f; do
    log WARN "Truncating large log: ${f}"
    : > "${f}"
  done

# 3. Clean old rotated logs
find "${LOG_ROOT}" -type f \( -name "*.gz" -o -name "*.old" -o -name "*.1" \) -mtime +14 -delete 2>/dev/null || true

# 4. Temporary directories
for t in "${TMP_ROOTS[@]}"; do
  find "${t}" -type f -mtime +3 -delete 2>/dev/null || true
  find "${t}" -type d -empty -mtime +1 -delete 2>/dev/null || true
done

# 5. Old kernels (keep current + one previous)
if command -v dnf >/dev/null; then
  dnf remove -y $(dnf repoquery --installonly --latest-limit=-2 -q) 2>/dev/null || true
fi

# 6. Inode pressure check
INODE_PCT=$(df -i / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ ${INODE_PCT} -gt ${INODE_THRESHOLD} ]]; then
  log ERROR "Inode usage critical: ${INODE_PCT}%"
  # Aggressive small-file cleanup under /var/tmp and /tmp only
  find /tmp /var/tmp -type f -size -1k -mtime +1 -delete 2>/dev/null || true
fi

# 7. Final report
USE_PCT=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ ${USE_PCT} -gt ${THRESHOLD_PCT} ]]; then
  log ERROR "Root filesystem still above ${THRESHOLD_PCT}% after hygiene (${USE_PCT}%)"
  exit 1
fi

log INFO "Disk hygiene completed (root=${USE_PCT}%)"
