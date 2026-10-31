#!/bin/bash
# selinux-app-harden.sh — force enforcing + fix contexts for common app paths

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

APP_PATHS=("/opt/app" "/var/lib/app" "/var/log/app" "/srv/app")
CUSTOM_FC="/etc/selinux/targeted/contexts/files/file_contexts.local"

# Ensure enforcing
if getenforce | grep -qi permissive; then
  log WARN "SELinux was permissive — setting to enforcing"
  setenforce 1
  sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
fi

# Restore standard contexts
for p in "${APP_PATHS[@]}"; do
  if [[ -d "${p}" ]]; then
    log INFO "restorecon -Rv ${p}"
    restorecon -Rv "${p}" >/dev/null || true
  fi
done

# Example custom fcontext (adjust to your real app)
# semanage fcontext -a -t httpd_sys_content_t "/opt/app(/.*)?"
# restorecon -Rv /opt/app

log INFO "SELinux mode: $(getenforce)"
