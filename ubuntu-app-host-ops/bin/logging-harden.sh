#!/bin/bash
# logging-harden.sh — journald size + ensure logging agents are alive (Ubuntu)

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

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

# Common agents on Ubuntu/AWS/Azure
for unit in rsyslog snap.amazon-ssm-agent.amazon-ssm-agent.service amazon-ssm-agent waagent; do
  if systemctl list-unit-files "${unit}" &>/dev/null || systemctl list-unit-files "${unit}.service" &>/dev/null; then
    systemctl is-active --quiet "${unit}" 2>/dev/null || systemctl start "${unit}" 2>/dev/null || true
    log INFO "Checked agent: ${unit}"
  fi
done
