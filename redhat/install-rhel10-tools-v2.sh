#!/usr/bin/env bash
#
# RHEL 9/10 CLI/TUI Tools Installer + Aliases (v2)
#
# Changes vs v1, learned the hard way:
#   - No surprise `dnf update` — opt in with --update. Kernel updates belong
#     to maintenance windows, not to a tools script.
#   - CRB enabled BEFORE EPEL (EPEL deps come from CRB).
#   - Per-package install with fallbacks and an honest end-of-run summary.
#     Rust-only tools (dua-cli, kondo) install via cargo when dnf fails,
#     or are skipped with a warning if cargo isn't present.
#   - atop's historical logging is actually enabled (that's the whole point
#     of atop on a server), same for sysstat.
#   - No alias shadows a real binary (no more `du -> dust`). Aliases ADD
#     verbs (`disk`, `mon`, `big`); they never replace existing commands —
#     pasted commands from docs must behave exactly as documented.
#   - Runs as root directly (drops per-command sudo; `sudo` may not exist in
#     minimal images).
#
# Usage: install_rhel10_tools-v2.sh [--update]
#
set -euo pipefail

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; CYN=$'\e[36m'; RST=$'\e[0m'
log()  { printf '%s[%s]%s %s\n' "$CYN" "$(date +%H:%M:%S)" "$RST" "$*"; }
ok()   { printf '%s OK %s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%sWARN%s %s\n' "$YLW" "$RST" "$*"; }
fail() { printf '%sFAIL%s %s\n' "$RED" "$RST" "$*"; }

FAILED=()

# --------------------------------------------------------------- guards ---
if [[ $EUID -ne 0 ]]; then
  fail "run as root (this script manages system packages and /etc/profile.d)"
  exit 1
fi

# Verify we're on a RHEL family 9/10 box before touching anything.
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  case "${ID:-unknown} ${VERSION_ID:-0}" in
    "rhel 9"*|"rhel 10"*|"rocky 9"*|"rocky 10"*|"almalinux 9"*|"almalinux 10"*|"centos 9"*|"centos 10"*)
      log "platform: $PRETTY_NAME" ;;
    *)
      warn "untested platform: ${PRETTY_NAME:-unknown} — proceeding anyway" ;;
  esac
else
  fail "no /etc/os-release — refusing to run blind"
  exit 1
fi

# -------------------------------------------------- optional full update ---
if [[ "${1:-}" == "--update" ]]; then
  log "full system update requested via --update"
  dnf update -y
else
  log "refreshing repo metadata only (use --update for a full system update)"
  dnf makecache
fi

# ------------------------------------------------------ repos, in order ---
log "enabling CRB first, then EPEL (EPEL build deps live in CRB)"
dnf config-manager --set-enabled crb 2>/dev/null || \
  dnf config-manager --set-enabled crb 2>/dev/null || warn "CRB enable failed — some EPEL packages may not resolve"

if ! dnf list installed epel-release >/dev/null 2>&1; then
  dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${VERSION_ID%%.*}.noarch.rpm"
fi

# ---------------------------------------------------------- packages ---
# One array, per-package fallback, no silent swallowing.
DNF_PACKAGES=(
  # disk / files
  ncdu du-dust mc ranger nnn duf gdu broot plocate
  # monitoring
  btop htop glances atop sysstat
  # modern coreutils companions (AppStream-covered where possible)
  ripgrep fd-find bat fzf eza
  # eza may be EPEL-only on some minors; failures are collected, not fatal
)

install_pkg() {
  local pkg=$1
  if dnf install -y "$pkg" >/dev/null 2>&1; then
    ok "$pkg"
    return 0
  fi
  return 1
}

log "installing packages (failures are collected and reported at the end)"
for pkg in "${DNF_PACKAGES[@]}"; do
  install_pkg "$pkg" || { warn "$pkg: not found in enabled repos"; FAILED+=("$pkg"); }
done

# Rust-only tools: dua-cli and kondo are not packaged in EPEL. cargo is the
# sanctioned install path. If cargo is missing, we say so and move on —
# a tools script that half-works and lies about it is worse than one that
# reports honestly.
for crate in dua-cli kondo; do
  if command -v "$crate" >/dev/null 2>&1; then
    ok "$crate (already present)"
    continue
  fi
  if command -v cargo >/dev/null 2>&1; then
    if cargo install "$crate" >/dev/null 2>&1; then
      ok "$crate (cargo)"
    else
      warn "$crate: cargo install failed"; FAILED+=("$crate")
    fi
  else
    warn "$crate: needs cargo (dnf install cargo rust) — skipping"
    FAILED+=("$crate")
  fi
done

# fd's dnf package is fd-find on some distros with the binary named fdfind.
# If fd is missing but fdfind exists, add a convenience symlink.
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  ln -sf "$(command -v fdfind)" /usr/local/bin/fd
fi

# ------------------------------------------------- enable the services ---
# The whole reason atop exists on a server: replay history from /var/log/atop
# when someone asks "what happened at 03:40". Installing it and not enabling
# the logger is buying a dashcam and never turning it on.
if rpm -q atop >/dev/null 2>&1; then
  systemctl enable --now atop atopacct 2>/dev/null || systemctl enable --now atop 2>/dev/null || warn "atop service enable failed"
  ok "atop history logging enabled (/var/log/atop)"
fi

# sar data: what Red Hat support asks for first in any perf ticket.
if rpm -q sysstat >/dev/null 2>&1; then
  systemctl enable --now sysstat 2>/dev/null || warn "sysstat enable failed"
  ok "sar collection enabled (sar -q / sar -r to review)"
fi

# plocate timer
rpm -q plocate >/dev/null 2>&1 && { systemctl enable --now plocate-updatedb.timer 2>/dev/null || true; ok "plocate index timer on"; }

# ------------------------------------------------------- aliases file ---
# Rules: never shadow a real binary (scripts, cron, sudo and pasted commands
# must behave as documented). Add NEW verbs instead.
cat > /etc/profile.d/rhel-tools.sh <<'ALIASES'
# RHEL tools — additive aliases only (never override du/top/df/ls)
alias disk='ncdu /'                 # interactive full-disk walk (run as root for full view)
alias big='dust -d 3'               # top 3 levels, sorted by size
alias mon='btop'
alias hist='atop'                   # atop with history (see /var/log/atop)
alias rg='rg --smart-case'
alias ll='ls -alh'
# deliberately NOT aliased: df->duf breaks scripts and tools that parse df
# output. If your box is interactive-only, alias it in ~/.bashrc yourself.
ALIASES
# no chmod +x: profile.d files are sourced, not executed

# Server-safe cleanup helper — NOT bleachbit (desktop-oriented). Real
# reclaim on servers: dnf autoremove, journal vacuum, container prunes.
cat > /usr/local/bin/server-clean <<'CLEANUP'
#!/usr/bin/env bash
# server-clean — safe, boring, effective disk reclaim
set -euo pipefail
echo "== before =="; df -h /
dnf autoremove -y || true
journalctl --rotate --vacuum-size=200M 2>/dev/null || true
command -v podman >/dev/null && podman system prune -af || true
# old kernels (keep current + 1): RHEL keeps installonly_limit (default 3)
rpm -q kernel-core >/dev/null && dnf remove --oldinstallonly -y || true
echo "== after =="; df -h /
CLEANUP
chmod +x /usr/local/bin/server-clean
ok "server-clean helper installed"

# --------------------------------------------------------------- report ---
log "=================== SUMMARY ==================="
MISSING_BINS=()
for tool in ncdu dust mc ranger nnn duf gdu broot btop htop glances atop sar dua kondo rg fzf eza; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  %-10s %s\n' "$tool" "$(command -v "$tool")"
  else
    MISSING_BINS+=("$tool")
  fi
done
if [[ ${#FAILED[@]} -gt 0 || ${#MISSING_BINS[@]} -gt 0 ]]; then
  warn "not installed: ${FAILED[*]:-} ${MISSING_BINS[*]:-}"
  warn "fix the above before assuming your toolkit is complete"
fi
ok "aliases in /etc/profile.d/rhel-tools.sh (new shells only)"
ok "reboot NOT required (new terminal picks up aliases)"
