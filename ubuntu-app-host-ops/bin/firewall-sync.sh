#!/bin/bash
# firewall-sync.sh — keep ufw (or firewalld) as second-line defense on Ubuntu

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

# Ports your application actually needs (adjust as required)
ALLOWED_PORTS=("22" "80" "443" "8080")

if command -v ufw >/dev/null 2>&1; then
  log INFO "Using ufw"
  ufw --force reset >/dev/null 2>&1 || true
  ufw default deny incoming
  ufw default allow outgoing

  for p in "${ALLOWED_PORTS[@]}"; do
    ufw allow "${p}/tcp" >/dev/null
  done

  ufw --force enable
  log INFO "ufw status: $(ufw status | head -5 | tr '\n' ' ')"
elif command -v firewall-cmd >/dev/null 2>&1; then
  log INFO "Using firewalld"
  systemctl is-active --quiet firewalld || systemctl start firewalld
  firewall-cmd --permanent --zone=public --remove-service=ssh 2>/dev/null || true
  for p in "${ALLOWED_PORTS[@]}"; do
    firewall-cmd --permanent --zone=public --add-port="${p}/tcp" 2>/dev/null || true
  done
  firewall-cmd --reload
  log INFO "firewalld ports: $(firewall-cmd --zone=public --list-ports)"
else
  log WARN "Neither ufw nor firewalld found — installing ufw"
  apt-get update -qq
  apt-get install -y ufw
  ufw default deny incoming
  ufw default allow outgoing
  for p in "${ALLOWED_PORTS[@]}"; do
    ufw allow "${p}/tcp"
  done
  ufw --force enable
fi
