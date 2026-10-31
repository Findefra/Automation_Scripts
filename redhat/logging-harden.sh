#!/bin/bash
# logging-harden.sh — journald size + ensure logging agents are alive

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

# Harden journald
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-ops.conf << EOF
[Journal]
SystemMaxUse=500M
SystemKeepFree=1G
MaxRetentionSec=7day
Compress=yes
EOF

systemctl restart systemd-journald
log INFO "journald hardened"

# Ensure common agents are running (adjust names to your environment)
for unit in rsyslog amazon-ssm-agent waagent; do
  if systemctl list-unit-files "${unit}.service" &>/dev/null; then
    systemctl is-active --quiet "${unit}" || systemctl start "${unit}"
    log INFO "${unit} is active"
  fi
done