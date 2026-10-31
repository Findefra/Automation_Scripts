#!/bin/bash
# ssh-harden.sh — lock down SSH for Ubuntu application hosts

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP="/etc/ssh/sshd_config.ops-bak.$(date +%s)"

cp "${SSHD_CONFIG}" "${BACKUP}"

sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' "${SSHD_CONFIG}"
sed -i -E 's/^#?PermitRootLogin.*/PermitRootLogin no/' "${SSHD_CONFIG}"
sed -i -E 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/' "${SSHD_CONFIG}"
sed -i -E 's/^#?MaxAuthTries.*/MaxAuthTries 3/' "${SSHD_CONFIG}"
sed -i -E 's/^#?ClientAliveInterval.*/ClientAliveInterval 300/' "${SSHD_CONFIG}"
sed -i -E 's/^#?ClientAliveCountMax.*/ClientAliveCountMax 2/' "${SSHD_CONFIG}"

if ! grep -q "^Ciphers " "${SSHD_CONFIG}"; then
  echo "Ciphers wendy.h@example.net,uma.s@example.org,hannah.h@example.com" >> "${SSHD_CONFIG}"
fi

sshd -t && systemctl reload sshd
log INFO "sshd hardened and reloaded (backup: ${BACKUP})"
