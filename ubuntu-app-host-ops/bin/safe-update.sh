#!/bin/bash
# safe-update.sh — gated apt update + reboot decision with health gate (Ubuntu)
# Real-world: never reboot without proving the application is still healthy.

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

LOCKFILE="/var/run/ops-safe-update.lock"
mkdir -p /var/log/ops

exec 200>"${LOCKFILE}"
if ! flock -n 200; then
  log WARN "Another update is already running — exiting"
  exit 0
fi

DRY_RUN=false
FORCE_REBOOT=false
APP_UNIT="${APP_UNIT:-}"
HEALTH_URL="${HEALTH_URL:-}"

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

if [[ -f /etc/ops/maintenance-window ]]; then
  if ! grep -q "$(date +%H)" /etc/ops/maintenance-window 2>/dev/null; then
    log INFO "Outside maintenance window — skipping"
    exit 0
  fi
fi

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

if [[ "${DRY_RUN}" == "true" ]]; then
  log INFO "Dry-run: would run apt update && apt upgrade -y"
  apt-get update -qq
  apt-get upgrade --dry-run 2>/dev/null || true
  exit 0
fi

log INFO "Running apt update && apt upgrade -y"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get autoremove -y

NEEDS_REBOOT=false
if [[ -f /var/run/reboot-required ]]; then
  NEEDS_REBOOT=true
elif [[ "${FORCE_REBOOT}" == "true" ]]; then
  NEEDS_REBOOT=true
fi

if [[ "${NEEDS_REBOOT}" == "false" ]]; then
  log INFO "No reboot required"
  exit 0
fi

log WARN "Reboot required — performing post-update health gate"

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
