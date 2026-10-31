#!/bin/bash
# apparmor-harden.sh — ensure AppArmor is active and common profiles are enforcing
# Ubuntu uses AppArmor by default (not SELinux).

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

if ! command -v aa-status >/dev/null 2>&1; then
  log WARN "AppArmor tools not installed — installing apparmor"
  apt-get update -qq
  apt-get install -y apparmor apparmor-utils
fi

systemctl is-active --quiet apparmor || systemctl start apparmor
systemctl enable apparmor 2>/dev/null || true

# Ensure common profiles are in enforce mode where present
for profile in /etc/apparmor.d/*; do
  [[ -f "${profile}" ]] || continue
  name=$(basename "${profile}")
  # Skip abstractions and tunables
  [[ "${name}" == abstractions* || "${name}" == tunables* || "${name}" == local* ]] && continue
  if aa-status 2>/dev/null | grep -q "${name}.*complain"; then
    log INFO "Setting ${name} to enforce"
    aa-enforce "${profile}" 2>/dev/null || true
  fi
done

log INFO "AppArmor status:"
aa-status --enabled 2>/dev/null && log INFO "AppArmor is enabled" || log WARN "AppArmor not fully enabled"
