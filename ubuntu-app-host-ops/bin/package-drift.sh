#!/bin/bash
# package-drift.sh — record and detect unexpected package changes (Ubuntu/apt)

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

BASELINE="/var/lib/ops/package-baseline.txt"
CURRENT="/var/lib/ops/package-current.txt"
mkdir -p /var/lib/ops

dpkg-query -W -f='${Package}\t${Version}\n' | sort > "${CURRENT}"

if [[ ! -f "${BASELINE}" ]]; then
  cp "${CURRENT}" "${BASELINE}"
  log INFO "Created initial package baseline"
  exit 0
fi

if ! diff -q "${BASELINE}" "${CURRENT}" >/dev/null; then
  log WARN "Package drift detected"
  diff -u "${BASELINE}" "${CURRENT}" | tee -a /var/log/ops/package-drift.log || true
else
  log INFO "No package drift"
fi
