#!/bin/bash
# app-watchdog.sh — simple application unit + health probe (Ubuntu)

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

APP_UNIT="${APP_UNIT:-myapp.service}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8080/health}"
MAX_FAILURES=3
STATE_FILE="/var/run/ops-app-watchdog.state"

failures=0
[[ -f "${STATE_FILE}" ]] && failures=$(cat "${STATE_FILE}")

healthy=true

if ! systemctl is-active --quiet "${APP_UNIT}"; then
  log WARN "${APP_UNIT} is not active"
  healthy=false
fi

if [[ -n "${HEALTH_URL}" ]]; then
  if ! curl -sf -m 3 "${HEALTH_URL}" >/dev/null; then
    log WARN "Health URL ${HEALTH_URL} failed"
    healthy=false
  fi
fi

if [[ "${healthy}" == "true" ]]; then
  echo 0 > "${STATE_FILE}"
  exit 0
fi

failures=$((failures + 1))
echo "${failures}" > "${STATE_FILE}"
log WARN "Failure count now ${failures}/${MAX_FAILURES}"

if [[ ${failures} -ge ${MAX_FAILURES} ]]; then
  log ERROR "Restarting ${APP_UNIT}"
  systemctl restart "${APP_UNIT}"
  echo 0 > "${STATE_FILE}"
fi
