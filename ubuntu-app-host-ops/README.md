# Ubuntu Application Host Operations Scripts (AWS + Azure)

**Real-world collection of 12 battle-tested scripts for Ubuntu application hosts running in AWS or Azure.**

Adapted from the RHEL versions for Ubuntu 20.04 / 22.04 / 24.04 LTS. Uses `apt`, native reboot signaling (`/var/run/reboot-required`), `ufw` (or firewalld if present), and AppArmor awareness.

These scripts focus on the failure modes that actually cause outages on Ubuntu fleets: disk-full from journald/log storms, post-unattended-upgrade reboots that take the app down, silent package drift, and missing health gates.

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
    ├── apparmor-harden.sh
    ├── firewall-sync.sh
    ├── app-watchdog.sh
    ├── package-drift.sh
    ├── logging-harden.sh
    ├── ssh-harden.sh
    ├── graceful-drain.sh
    └── daily-snapshot.sh

/var/log/ops/
/var/lib/ops/
```

Install:

```bash
mkdir -p /opt/ops/{lib,bin} /var/log/ops /var/lib/ops
chown -R root:root /opt/ops
chmod 750 /opt/ops/bin/*
chmod 640 /opt/ops/lib/*
```

---

## Core Design Principles

- Prefer token-based metadata (IMDSv2 / Azure Metadata).
- Patching = `apt upgrade` → health gate → reboot decision → evidence.
- Disk full is still the #1 silent killer on Ubuntu (journald + logrotate gaps).
- AppArmor is the Ubuntu default; enforce profiles for the application where practical.
- Every script is idempotent, lock-protected, and logs structured output.

---

## Scripts Overview

| # | Script | Purpose |
|---|--------|---------|
| 1 | `cloud-info.sh` | Cloud detection + structured logging library |
| 2 | `safe-update.sh` | Gated `apt` update + reboot with health checks |
| 3 | `disk-hygiene.sh` | Aggressive but safe disk/inode cleanup |
| 4 | `apply-sysctl.sh` | Application-host tuned sysctl |
| 5 | `apparmor-harden.sh` | AppArmor status + enforce common profiles |
| 6 | `firewall-sync.sh` | ufw (or firewalld) second-line defense |
| 7 | `app-watchdog.sh` | Application unit + health probe |
| 8 | `package-drift.sh` | Detect unexpected package changes |
| 9 | `logging-harden.sh` | journald limits + agent health |
| 10 | `ssh-harden.sh` | SSH lockdown |
| 11 | `graceful-drain.sh` | ASG / VMSS scale-in drain |
| 12 | `daily-snapshot.sh` | Daily evidence pack |

See individual script files for full source and comments.

---

## Enabling with systemd timers

Same pattern as the RHEL set. Example for disk hygiene:

```ini
# /etc/systemd/system/ops-disk-hygiene.timer
[Unit]
Description=Run disk hygiene every 20 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=20min

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

```bash
systemctl daemon-reload
systemctl enable --now ops-disk-hygiene.timer
```

---

## Customization

| Variable | Purpose | Typical value |
|----------|---------|---------------|
| `APP_UNIT` | systemd unit of the application | `myapp.service` |
| `HEALTH_URL` | Local health endpoint | `http://127.0.0.1:8080/health` |
| `ALLOWED_PORTS` | Ports for ufw | `22,80,443,8080` |

---

## Notes specific to Ubuntu

- Reboot detection relies on `/var/run/reboot-required` (created by `unattended-upgrades` and kernel package installs).
- Prefer `needrestart` package for more accurate service restart decisions if you want finer control.
- AppArmor is used instead of SELinux. The harden script focuses on ensuring the daemon is active and common profiles are in enforce mode.
- `ufw` is the default firewall tool; the script falls back gracefully if firewalld is present instead.

These scripts form a practical baseline for Ubuntu application hosts on both AWS and Azure.
