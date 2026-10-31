#!/bin/bash
# safe-update.sh — gated dnf update + reboot decision with health gate
# Real-world: never reboot without proving the application is still healthy.

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

LOCKFILE="/var/run/ops-safe-update.lock"
LOGDIR="/var/log/ops"
mkdir -p "${LOGDIR}"

exec 200>"${LOCKFILE}"
if ! flock -n 200; then
  log WARN "Another update is already running — exiting"
  exit 0
fi

DRY_RUN=false
FORCE_REBOOT=false
APP_UNIT="${APP_UNIT:-}"          # e.g. myapp.service — set via env or systemd
HEALTH_URL="${HEALTH_URL:-}"      # e.g. http://127.0.0.1:8080/health
MAX_WAIT=300

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --force-reboot) FORCE_REBOOT=true; shift ;;
    --app-unit) APP_UNIT="$2"; shift 2 ;;
    --health-url) HEALTH_URL="$2"; shift 2 ;;
    *) log ERROR "Unknown argument: $1"; exit 1 ;;
  esac
done

log INFO "Starting safe update (dry-run=${DRY_RUN})"

# 1. Optional maintenance window check (tag or file)
if [[ -f /etc/ops/maintenance-window ]]; then
  if ! grep -q "$(date +%H)" /etc/ops/maintenance-window 2>/dev/null; then
    log INFO "Outside maintenance window — skipping"
    exit 0
  fi
fi

# 2. Pre-flight health
if [[ -n "${APP_UNIT}" ]]; then
  if ! systemctl is-active --quiet "${APP_UNIT}"; then
    log ERROR "Application unit ${APP_UNIT} is not active — aborting update"
    exit 1
  fi
fi

if [[ -n "${HEALTH_URL}" ]]; then
  if ! curl -sf -m 5 "${HEALTH_URL}" >/dev/null; then
    log ERROR "Health check ${HEALTH_URL} failed before update — aborting"
    exit 1
  fi
fi

# 3. Apply updates
if [[ "${DRY_RUN}" == "true" ]]; then
  log INFO "Dry-run: would run dnf update -y"
  dnf check-update || true
  exit 0
fi

log INFO "Running dnf update -y"
dnf clean all
dnf update -y --setopt=install_weak_deps=False

# 4. Decide reboot
NEEDS_REBOOT=false
if command -v needs-restarting >/dev/null 2>&1; then
  if needs-restarting -r >/dev/null 2>&1; then
    NEEDS_REBOOT=true
  fi
elif [[ -f /var/run/reboot-required ]]; then
  NEEDS_REBOOT=true
fi

if [[ "${FORCE_REBOOT}" == "true" ]]; then
  NEEDS_REBOOT=true
fi

if [[ "${NEEDS_REBOOT}" == "false" ]]; then
  log INFO "No reboot required"
  exit 0
fi

log WARN "Reboot required — performing post-update health gate"

# 5. Post-update health before reboot
if [[ -n "${APP_UNIT}" ]]; then
  systemctl restart "${APP_UNIT}" || true
  sleep 10
  if ! systemctl is-active --quiet "${APP_UNIT}"; then
    log ERROR "Application unit failed after update — NOT rebooting"
    exit 1
  fi
fi

if [[ -n "${HEALTH_URL}" ]]; then
  for i in $(seq 1 12); do
    if curl -sf -m 5 "${HEALTH_URL}" >/dev/null; then
      log INFO "Health check passed after update"
      break
    fi
    if [[ $i -eq 12 ]]; then
      log ERROR "Health check still failing after update — NOT rebooting"
      exit 1
    fi
    sleep 10
  done
fi

log WARN "Rebooting in 5 seconds..."
sleep 5
systemctl reboot
