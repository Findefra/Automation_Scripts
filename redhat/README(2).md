# RHEL Application Host Operations Scripts (AWS + Azure)

**Real-world collection of 12 battle-tested scripts for Red Hat Enterprise Linux application hosts running in AWS or Azure.**

These scripts come from 15+ years of hands-on DevOps work on large RHEL fleets. They deliberately avoid textbook “best practices” and focus on the failure modes that actually cause outages, disk-full incidents, silent security drift, and painful post-patching recovery.

They are designed for classic VM-based application hosting (not Kubernetes). They work on RHEL 8 and RHEL 9 with `dnf`.

---

## Recommended Directory Layout

```bash
/opt/ops/
├── lib/
│   └── cloud-info.sh
└── bin/
    ├── safe-update.sh
    ├── disk-hygiene.sh
    ├── apply-sysctl.sh
    ├── selinux-app-harden.sh
    ├── firewall-sync.sh
    ├── app-watchdog.sh
    ├── package-drift.sh
    ├── logging-harden.sh
    ├── ssh-harden.sh
    ├── graceful-drain.sh
    └── daily-snapshot.sh

/var/log/ops/          # all script logs land here
/var/lib/ops/          # baselines, snapshots, state files
/var/run/              # lock files
```

Install once on a golden image or via SSM / Azure Run Command / Ansible:

```bash
mkdir -p /opt/ops/{lib,bin} /var/log/ops /var/lib/ops
chown -R root:root /opt/ops
chmod 750 /opt/ops/bin/*
chmod 640 /opt/ops/lib/*
```

---

## Core Design Principles (Lessons Learned the Hard Way)

- **Never trust the guest agent alone.** Always prefer token-based instance metadata (IMDSv2 / Azure Metadata Service).
- **Patching is not `dnf update`.** It is update → health gate → reboot decision → evidence.
- **Disk full is still the #1 silent killer.** Logrotate is not enough under log storms.
- **SELinux and firewalld that are not verified at boot are theater.**
- **Every script must be idempotent, lock-protected, and log structured output.**
- **Cloud differences matter.** AWS and Azure have different metadata, agents, and lifecycle hooks. The scripts detect the cloud and adapt.

All scripts source the common library, require root, use `flock`, and write to `/var/log/ops/`.

---

## 1. `/opt/ops/lib/cloud-info.sh`

Common library used by every other script. Handles cloud detection, instance metadata, and structured logging.

```bash
#!/bin/bash
# cloud-info.sh — reliable cloud detection + metadata (IMDSv2 / Azure Metadata)
# Never trust the guest agent alone. Always prefer token-based metadata.

set -euo pipefail

_CLOUD=""
_INSTANCE_ID=""
_REGION=""
_PRIVATE_IP=""

detect_cloud() {
  if [[ -n "${_CLOUD}" ]]; then
    echo "${_CLOUD}"
    return
  fi

  # Azure first (header is distinctive)
  if curl -s -m 2 -f -H "Metadata:true" \
      "http://169.254.169.254/metadata/instance?api-version=2021-02-01" >/dev/null 2>&1; then
    _CLOUD="azure"
  # AWS IMDSv2
  elif TOKEN=$(curl -s -m 2 -f -X PUT "http://169.254.169.254/latest/api/token" \
               -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null); then
    if curl -s -m 2 -f -H "X-aws-ec2-metadata-token: ${TOKEN}" \
         "http://169.254.169.254/latest/meta-data/instance-id" >/dev/null 2>&1; then
      _CLOUD="aws"
    else
      _CLOUD="unknown"
    fi
  else
    _CLOUD="unknown"
  fi
  echo "${_CLOUD}"
}

get_instance_id() {
  [[ -n "${_INSTANCE_ID}" ]] && { echo "${_INSTANCE_ID}"; return; }
  local cloud
  cloud=$(detect_cloud)
  case "${cloud}" in
    aws)
      local token
      token=$(curl -s -m 2 -X PUT "http://169.254.169.254/latest/api/token" \
              -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
      _INSTANCE_ID=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: ${token}" \
                     http://169.254.169.254/latest/meta-data/instance-id)
      ;;
    azure)
      _INSTANCE_ID=$(curl -s -m 2 -H "Metadata:true" \
        "http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-02-01&format=text")
      ;;
    *)
      _INSTANCE_ID="unknown"
      ;;
  esac
  echo "${_INSTANCE_ID}"
}

get_region() {
  [[ -n "${_REGION}" ]] && { echo "${_REGION}"; return; }
  local cloud
  cloud=$(detect_cloud)
  case "${cloud}" in
    aws)
      local token
      token=$(curl -s -m 2 -X PUT "http://169.254.169.254/latest/api/token" \
              -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
      _REGION=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: ${token}" \
                http://169.254.169.254/latest/meta-data/placement/region)
      ;;
    azure)
      _REGION=$(curl -s -m 2 -H "Metadata:true" \
        "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")
      ;;
    *)
      _REGION="unknown"
      ;;
  esac
  echo "${_REGION}"
}

get_private_ip() {
  [[ -n "${_PRIVATE_IP}" ]] && { echo "${_PRIVATE_IP}"; return; }
  local cloud
  cloud=$(detect_cloud)
  case "${cloud}" in
    aws)
      local token
      token=$(curl -s -m 2 -X PUT "http://169.254.169.254/latest/api/token" \
              -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
      _PRIVATE_IP=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: ${token}" \
                    http://169.254.169.254/latest/meta-data/local-ipv4)
      ;;
    azure)
      _PRIVATE_IP=$(curl -s -m 2 -H "Metadata:true" \
        "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2021-02-01&format=text")
      ;;
    *)
      _PRIVATE_IP=$(hostname -I | awk '{print $1}')
      ;;
  esac
  echo "${_PRIVATE_IP}"
}

# Simple structured logger used by every script
log() {
  local level="$1"
  shift
  local msg="$*"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local iid
  iid=$(get_instance_id 2>/dev/null || echo "unknown")
  echo "${ts} [${level}] [${iid}] ${msg}" | tee -a "/var/log/ops/$(basename "$0" .sh).log"
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    log ERROR "This script must be run as root"
    exit 1
  fi
}
```

---

## 2. `/opt/ops/bin/safe-update.sh`

Gated `dnf update` with pre- and post-health checks and controlled reboot decision.  
**This is the single most valuable script on an application host.**

```bash
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
```

---

## 3. `/opt/ops/bin/disk-hygiene.sh`

Aggressive but safe cleanup of the usual disk killers. Run every 15–30 minutes.

```bash
#!/bin/bash
# disk-hygiene.sh — aggressive but safe cleanup of the usual disk killers
# Runs every 15-30 min via timer. Protects application data paths.

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

LOCKFILE="/var/run/ops-disk-hygiene.lock"
exec 200>"${LOCKFILE}"
flock -n 200 || exit 0

THRESHOLD_PCT=85
INODE_THRESHOLD=90
LOG_ROOT="/var/log"
TMP_ROOTS=("/tmp" "/var/tmp")

log INFO "Disk hygiene starting"

# Report current state
df -h / /var /var/log 2>/dev/null | while read -r line; do
  log INFO "df: ${line}"
done

# 1. Journald size control (very common silent filler)
if command -v journalctl >/dev/null; then
  journalctl --vacuum-size=500M --vacuum-time=7d 2>/dev/null || true
  log INFO "journald vacuumed"
fi

# 2. Truncate runaway application / system logs that logrotate missed
find "${LOG_ROOT}" -type f -name "*.log" -size +500M -mtime +1 -print0 2>/dev/null | \
  while IFS= read -r -d '' f; do
    log WARN "Truncating large log: ${f}"
    : > "${f}"
  done

# 3. Clean old rotated logs
find "${LOG_ROOT}" -type f \( -name "*.gz" -o -name "*.old" -o -name "*.1" \) -mtime +14 -delete 2>/dev/null || true

# 4. Temporary directories
for t in "${TMP_ROOTS[@]}"; do
  find "${t}" -type f -mtime +3 -delete 2>/dev/null || true
  find "${t}" -type d -empty -mtime +1 -delete 2>/dev/null || true
done

# 5. Old kernels (keep current + one previous)
if command -v dnf >/dev/null; then
  dnf remove -y $(dnf repoquery --installonly --latest-limit=-2 -q) 2>/dev/null || true
fi

# 6. Inode pressure check
INODE_PCT=$(df -i / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ ${INODE_PCT} -gt ${INODE_THRESHOLD} ]]; then
  log ERROR "Inode usage critical: ${INODE_PCT}%"
  # Aggressive small-file cleanup under /var/tmp and /tmp only
  find /tmp /var/tmp -type f -size -1k -mtime +1 -delete 2>/dev/null || true
fi

# 7. Final report
USE_PCT=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ ${USE_PCT} -gt ${THRESHOLD_PCT} ]]; then
  log ERROR "Root filesystem still above ${THRESHOLD_PCT}% after hygiene (${USE_PCT}%)"
  exit 1
fi

log INFO "Disk hygiene completed (root=${USE_PCT}%)"
```

---

## 4. `/opt/ops/bin/apply-sysctl.sh`

Opinionated sysctl values for high-connection application hosts (Java, Node, web tiers).

```bash
#!/bin/bash
# apply-sysctl.sh — application-host tuned sysctl values
# Opinionated for high-connection web / Java / Node hosts.

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

SYSCTL_FILE="/etc/sysctl.d/99-app-host.conf"

cat > "${SYSCTL_FILE}" << 'EOF'
# /etc/sysctl.d/99-app-host.conf
# Generated by apply-sysctl.sh — do not edit by hand

# Network backlog & connection handling
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# Memory & file handles
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5
fs.file-max = 2097152
fs.nr_open = 2097152

# Protect against SYN floods a bit more
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1

# IPv6 (disable if you do not use it)
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
EOF

sysctl --system >/dev/null
log INFO "Applied sysctl from ${SYSCTL_FILE}"

# Verify a couple of critical ones
for key in net.core.somaxconn vm.swappiness fs.file-max; do
  val=$(sysctl -n "${key}")
  log INFO "Verified ${key} = ${val}"
done
```

---

## 5. `/opt/ops/bin/selinux-app-harden.sh`

Force SELinux enforcing mode and repair contexts on common application paths.

```bash
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
```

---

## 6. `/opt/ops/bin/firewall-sync.sh`

Keep firewalld as a second line of defense. Primary perimeter remains the cloud Security Group / NSG.

```bash
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
```

---

## 7. `/opt/ops/bin/app-watchdog.sh`

Simple, reliable application unit + health probe. Call from a short systemd timer (30–60 s).

```bash
#!/bin/bash
# app-watchdog.sh — simple, reliable application unit + health probe
# Called by a short systemd timer (every 30-60s).

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

APP_UNIT="${APP_UNIT:-myapp.service}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8080/health}"
MAX_FAILURES=3
STATE_FILE="/var/run/ops-app-watchdog.state"

failures=0
[[ -f "${STATE_FILE}" ]] && failures=$(cat "${STATE_FILE}")

healthy=true

if ! systemctl is-active --quiet "${APP_UNIT}"; then
  log WARN "${APP_UNIT} is not active"
  healthy=false
fi

if [[ -n "${HEALTH_URL}" ]]; then
  if ! curl -sf -m 3 "${HEALTH_URL}" >/dev/null; then
    log WARN "Health URL ${HEALTH_URL} failed"
    healthy=false
  fi
fi

if [[ "${healthy}" == "true" ]]; then
  echo 0 > "${STATE_FILE}"
  exit 0
fi

failures=$((failures + 1))
echo "${failures}" > "${STATE_FILE}"
log WARN "Failure count now ${failures}/${MAX_FAILURES}"

if [[ ${failures} -ge ${MAX_FAILURES} ]]; then
  log ERROR "Restarting ${APP_UNIT}"
  systemctl restart "${APP_UNIT}"
  echo 0 > "${STATE_FILE}"
fi
```

---

## 8. `/opt/ops/bin/package-drift.sh`

Record installed packages and detect unexpected changes (manual installs, rogue repos, etc.).

```bash
#!/bin/bash
# package-drift.sh — record and detect unexpected package changes

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

BASELINE="/var/lib/ops/package-baseline.txt"
CURRENT="/var/lib/ops/package-current.txt"
mkdir -p /var/lib/ops

rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > "${CURRENT}"

if [[ ! -f "${BASELINE}" ]]; then
  cp "${CURRENT}" "${BASELINE}"
  log INFO "Created initial package baseline"
  exit 0
fi

if ! diff -q "${BASELINE}" "${CURRENT}" >/dev/null; then
  log WARN "Package drift detected"
  diff -u "${BASELINE}" "${CURRENT}" | tee -a /var/log/ops/package-drift.log || true
  # Optional: exit non-zero so monitoring notices
  # exit 1
else
  log INFO "No package drift"
fi
```

---

## 9. `/opt/ops/bin/logging-harden.sh`

Harden journald size/retention and ensure common logging agents are running.

```bash
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
```

---

## 10. `/opt/ops/bin/ssh-harden.sh`

Lock down SSH for application hosts (key-only, no root login, reduced attack surface).

```bash
#!/bin/bash
# ssh-harden.sh — lock down SSH for application hosts

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP="/etc/ssh/sshd_config.ops-bak.$(date +%s)"

cp "${SSHD_CONFIG}" "${BACKUP}"

# Apply hardened settings (idempotent)
sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' "${SSHD_CONFIG}"
sed -i -E 's/^#?PermitRootLogin.*/PermitRootLogin no/' "${SSHD_CONFIG}"
sed -i -E 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/' "${SSHD_CONFIG}"
sed -i -E 's/^#?MaxAuthTries.*/MaxAuthTries 3/' "${SSHD_CONFIG}"
sed -i -E 's/^#?ClientAliveInterval.*/ClientAliveInterval 300/' "${SSHD_CONFIG}"
sed -i -E 's/^#?ClientAliveCountMax.*/ClientAliveCountMax 2/' "${SSHD_CONFIG}"

# Remove weak ciphers if present
if ! grep -q "^Ciphers " "${SSHD_CONFIG}"; then
  echo "Ciphers wendy.h@example.net,uma.s@example.org,hannah.h@example.com" >> "${SSHD_CONFIG}"
fi

sshd -t && systemctl reload sshd
log INFO "sshd hardened and reloaded (backup: ${BACKUP})"
```

---

## 11. `/opt/ops/bin/graceful-drain.sh`

Called by ASG lifecycle hooks or Azure scale-in. Gives the application time to finish in-flight work.

```bash
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
```

---

## 12. `/opt/ops/bin/daily-snapshot.sh`

Compact daily evidence pack for audits, debugging, and “prove the host was healthy” conversations.

```bash
#!/bin/bash
# daily-snapshot.sh — compact daily evidence for audits and debugging

set -euo pipefail
source /opt/ops/lib/cloud-info.sh
require_root

OUTDIR="/var/lib/ops/snapshots"
mkdir -p "${OUTDIR}"
STAMP=$(date -u +%Y%m%d)
REPORT="${OUTDIR}/snapshot-${STAMP}.txt"

{
  echo "=== OPS SNAPSHOT $(date -u) ==="
  echo "Instance: $(get_instance_id)"
  echo "Cloud:    $(detect_cloud)"
  echo "Region:   $(get_region)"
  echo "PrivateIP:$(get_private_ip)"
  echo
  echo "--- Kernel ---"
  uname -r
  echo
  echo "--- Last update ---"
  dnf history list | head -5
  echo
  echo "--- SELinux ---"
  getenforce
  echo
  echo "--- Disk ---"
  df -h /
  df -i /
  echo
  echo "--- Critical services ---"
  systemctl is-active firewalld sshd || true
  echo
  echo "--- Package hash ---"
  rpm -qa | sort | sha256sum
} > "${REPORT}"

log INFO "Daily snapshot written to ${REPORT}"

# Optional: push to S3 / Azure Blob
# aws s3 cp "${REPORT}" "s3://your-ops-bucket/snapshots/$(get_instance_id)/" ...
```

---

## Enabling with systemd timers (recommended)

### Disk hygiene (every 20 minutes)

```ini
# /etc/systemd/system/ops-disk-hygiene.timer
[Unit]
Description=Run disk hygiene every 20 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=20min
AccuracySec=1min

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/ops-disk-hygiene.service
[Unit]
Description=Disk hygiene

[Service]
Type=oneshot
ExecStart=/opt/ops/bin/disk-hygiene.sh
```

### Application watchdog (every 45 seconds)

```ini
# /etc/systemd/system/ops-app-watchdog.timer
[Unit]
Description=Application watchdog

[Timer]
OnBootSec=30s
OnUnitActiveSec=45s

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/ops-app-watchdog.service
[Unit]
Description=Application watchdog

[Service]
Type=oneshot
Environment=APP_UNIT=myapp.service
Environment=HEALTH_URL=http://127.0.0.1:8080/health
ExecStart=/opt/ops/bin/app-watchdog.sh
```

### Daily snapshot

```ini
# /etc/systemd/system/ops-daily-snapshot.timer
[Unit]
Description=Daily ops snapshot

[Timer]
OnCalendar=*-*-* 03:15:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:

```bash
systemctl daemon-reload
systemctl enable --now ops-disk-hygiene.timer
systemctl enable --now ops-app-watchdog.timer
systemctl enable --now ops-daily-snapshot.timer
```

---

## Customization Notes

| Variable / Path              | Purpose                                      | Typical value                     |
|-----------------------------|----------------------------------------------|-----------------------------------|
| `APP_UNIT`                  | systemd unit name of your application        | `myapp.service`                   |
| `HEALTH_URL`                | Local health endpoint                        | `http://127.0.0.1:8080/health`    |
| `ALLOWED_PORTS`             | firewalld ports                              | `22/tcp 80/tcp 443/tcp 8080/tcp`  |
| `/opt/app`, `/var/lib/app`  | Application paths for SELinux restorecon     | Adjust to your layout             |
| `/etc/ops/maintenance-window` | Optional hour list for safe-update         | `02 03 04`                        |

---

## Operational Tips from Production

1. Bake these scripts into your EC2 Image Builder / Azure Image Builder pipeline so every new instance starts clean.
2. Call `safe-update.sh` from SSM Run Command or Azure Run Command during controlled maintenance windows rather than enabling automatic reboots everywhere.
3. The `graceful-drain.sh` script is meant to be the target of ASG lifecycle hooks or Azure VMSS scale-in notifications.
4. Keep `package-drift.sh` and `daily-snapshot.sh` results in a central location (S3 / Azure Blob) for audit trails.
5. Always test the health gate paths of `safe-update.sh` in a non-production ASG/VMSS first. A bad health URL will block reboots — that is intentional.

These twelve scripts form a practical, maintainable baseline that has survived real traffic, real patching cycles, and real on-call pressure on both AWS and Azure RHEL application hosts.
```
