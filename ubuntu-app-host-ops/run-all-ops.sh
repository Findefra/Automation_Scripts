#!/bin/bash
# run-all-ops.sh — Master runner for Ubuntu application-host ops scripts
# Executes the scripts under /opt/ops (or relative to this file) in a safe order.
#
# Usage:
#   ./run-all-ops.sh                  # run all (interactive confirmation)
#   ./run-all-ops.sh --yes            # run all without confirmation
#   ./run-all-ops.sh --dry-run        # show what would run
#   ./run-all-ops.sh --only disk-hygiene,logging-harden
#   ./run-all-ops.sh --skip safe-update,graceful-drain
#   APP_UNIT=myapp.service HEALTH_URL=http://127.0.0.1:8080/health ./run-all-ops.sh --yes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
BIN_DIR="${SCRIPT_DIR}/bin"

# Prefer installed location if present
if [[ -d /opt/ops/bin ]]; then
  BIN_DIR="/opt/ops/bin"
  LIB_DIR="/opt/ops/lib"
fi

# Source cloud-info if available (for consistent logging)
if [[ -f "${LIB_DIR}/cloud-info.sh" ]]; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/cloud-info.sh"
else
  log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$1] $*"; }
  require_root() { [[ $EUID -eq 0 ]] || { echo "Must run as root"; exit 1; }; }
fi

require_root

DRY_RUN=false
ASSUME_YES=false
ONLY=""
SKIP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=true; shift ;;
    --yes|-y)    ASSUME_YES=true; shift ;;
    --only)      ONLY="$2"; shift 2 ;;
    --skip)      SKIP="$2"; shift 2 ;;
    -h|--help)
      cat << EOF
Usage: $0 [OPTIONS]

  --dry-run          Show what would be executed without running
  --yes, -y          Skip confirmation prompt
  --only LIST        Comma-separated list of script basenames to run
  --skip LIST        Comma-separated list of script basenames to skip
  -h, --help         Show this help

Environment variables respected by child scripts:
  APP_UNIT           systemd unit name (default: myapp.service)
  HEALTH_URL         local health endpoint
  DRAIN_SECONDS      graceful drain timeout

Examples:
  $0 --yes
  $0 --only disk-hygiene,logging-harden,daily-snapshot
  $0 --skip safe-update,graceful-drain --yes
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Ordered list — safe-update and graceful-drain are intentionally later / optional
SCRIPTS=(
  "apply-sysctl.sh"
  "apparmor-harden.sh"
  "firewall-sync.sh"
  "logging-harden.sh"
  "ssh-harden.sh"
  "disk-hygiene.sh"
  "package-drift.sh"
  "app-watchdog.sh"
  "daily-snapshot.sh"
  # These two are higher risk / context-specific — run last or via --only
  "safe-update.sh"
  "graceful-drain.sh"
)

should_run() {
  local name="$1"
  local base="${name%.sh}"

  if [[ -n "${ONLY}" ]]; then
    [[ ",${ONLY}," == *",${base},"* || ",${ONLY}," == *",${name},"* ]] && return 0
    return 1
  fi

  if [[ -n "${SKIP}" ]]; then
    [[ ",${SKIP}," == *",${base},"* || ",${SKIP}," == *",${name},"* ]] && return 1
  fi

  return 0
}

echo "============================================================"
echo " Ubuntu App-Host Ops Runner"
echo " BIN_DIR : ${BIN_DIR}"
echo " Dry-run : ${DRY_RUN}"
echo "============================================================"
echo

TO_RUN=()
for s in "${SCRIPTS[@]}"; do
  if should_run "$s"; then
    if [[ -x "${BIN_DIR}/${s}" || -f "${BIN_DIR}/${s}" ]]; then
      TO_RUN+=("$s")
    else
      log WARN "Script not found or not executable: ${BIN_DIR}/${s}"
    fi
  fi
done

if [[ ${#TO_RUN[@]} -eq 0 ]]; then
  log ERROR "No scripts selected to run"
  exit 1
fi

echo "Scripts that will run:"
for s in "${TO_RUN[@]}"; do
  echo "  - $s"
done
echo

if [[ "${DRY_RUN}" == "true" ]]; then
  log INFO "Dry-run complete — nothing executed"
  exit 0
fi

if [[ "${ASSUME_YES}" != "true" ]]; then
  read -r -p "Proceed with running the above scripts? [y/N] " ans
  if [[ ! "${ans}" =~ ^[Yy]$ ]]; then
    log INFO "Aborted by user"
    exit 0
  fi
fi

FAILED=0
for s in "${TO_RUN[@]}"; do
  echo
  log INFO "========== Running ${s} =========="
  if bash "${BIN_DIR}/${s}"; then
    log INFO "${s} completed successfully"
  else
    log ERROR "${s} failed (exit $?)"
    FAILED=$((FAILED + 1))
    # Continue with remaining scripts unless it was a critical one
    if [[ "$s" == "safe-update.sh" ]]; then
      log ERROR "safe-update failed — stopping further execution"
      break
    fi
  fi
done

echo
if [[ ${FAILED} -gt 0 ]]; then
  log ERROR "Finished with ${FAILED} failure(s)"
  exit 1
else
  log INFO "All selected scripts completed successfully"
  exit 0
fi
