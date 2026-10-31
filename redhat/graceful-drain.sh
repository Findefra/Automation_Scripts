#!/bin/bash
# graceful-drain.sh — called by ASG lifecycle hook or Azure scale-in
# Gives the application time to finish in-flight work.

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

APP_UNIT="${APP_UNIT:-myapp.service}"
DRAIN_SECONDS="${DRAIN_SECONDS:-45}"
HEALTH_URL="${HEALTH_URL:-}"

log INFO "Starting graceful drain for ${APP_UNIT}"

# Optional: take out of rotation if you manage target groups yourself
# (AWS CLI / Azure CLI calls would go here)

# Signal application to stop accepting new work (implementation-specific)
# systemctl kill -s SIGTERM "${APP_UNIT}" || true

if [[ -n "${HEALTH_URL}" ]]; then
  log INFO "Waiting up to ${DRAIN_SECONDS}s for health to go dark or connections to drain"
  for i in $(seq 1 "${DRAIN_SECONDS}"); do
    if ! curl -sf -m 1 "${HEALTH_URL}" >/dev/null 2>&1; then
      log INFO "Health endpoint no longer responding — drain complete"
      break
    fi
    sleep 1
  done
else
  sleep "${DRAIN_SECONDS}"
fi

# Final stop
systemctl stop "${APP_UNIT}" || true
log INFO "Graceful drain finished"