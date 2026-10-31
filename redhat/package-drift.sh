#!/bin/bash
# package-drift.sh — record and detect unexpected package changes

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

BASELINE="/var/lib/ops/package-baseline.txt"
CURRENT="/var/lib/ops/package-current.txt"
mkdir -p /var/lib/ops

rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > "${CURRENT}"

if [[ ! -f "${BASELINE}" ]]; then
  cp "${CURRENT}" "${BASELINE}"
  log INFO "Created initial package baseline"
  exit 0
fi

if ! diff -q "${BASELINE}" "${CURRENT}" >/dev/null; then
  log WARN "Package drift detected"
  diff -u "${BASELINE}" "${CURRENT}" | tee -a /var/log/ops/package-drift.log || true
  # Optional: exit non-zero so monitoring notices
  # exit 1
else
  log INFO "No package drift"
fi
