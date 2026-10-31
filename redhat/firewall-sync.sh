#!/bin/bash
# firewall-sync.sh — keep firewalld as a second line of defense
# Primary perimeter is the cloud SG/NSG. This only opens what is already allowed.

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

# Example: only allow the ports your application actually needs
# Adjust these to match your real services.
ALLOWED_PORTS=("22/tcp" "80/tcp" "443/tcp" "8080/tcp")

systemctl is-active --quiet firewalld || systemctl start firewalld

# Reset public zone to a known baseline
firewall-cmd --permanent --zone=public --remove-service=ssh 2>/dev/null || true
firewall-cmd --permanent --zone=public --remove-service=dhcpv6-client 2>/dev/null || true

for p in "${ALLOWED_PORTS[@]}"; do
  firewall-cmd --permanent --zone=public --add-port="${p}" 2>/dev/null || true
done

firewall-cmd --reload
log INFO "firewalld public zone ports: $(firewall-cmd --zone=public --list-ports)"
