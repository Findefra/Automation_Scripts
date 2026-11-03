#!/usr/bin/env bash
#
# Advanced AWS On-Premises → us-east-1 Migration Script
# AWS Application Migration Service (MGN / AWS Transform MGN)
#
# Features:
#   • Pre-migration backup (Linux + Windows guidance)
#   • Wave-based migration (create / list / process waves)
#   • Automatic instance-type right-sizing (BASIC)
#   • Launch test instances with adequate resources
#   • Detailed JSON report → S3
#
# Target Region: us-east-1
#
# Prerequisites:
#   - AWS CLI v2 + jq
#   - Credentials with mgn:*, s3:*, ec2:Describe*, iam:PassRole (if using instance profiles)
#   - AWS Replication Agent already installed on source servers
#   - Network connectivity from sources to AWS
#
# Usage examples at the bottom of this file.
#

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# CONFIGURATION – EDIT THESE
# =============================================================================
AWS_REGION="us-east-1"
S3_REPORT_BUCKET="your-migration-reports-bucket"          # must exist
S3_REPORT_PREFIX="mgn-migration-reports"
BACKUP_S3_PREFIX="pre-migration-backups"

# Right-sizing & launch defaults
ENABLE_RIGHT_SIZING="true"          # true → BASIC, false → NONE
DEFAULT_INSTANCE_TYPE="m5.xlarge"   # used only when right-sizing is disabled
DEFAULT_SUBNET_ID=""                # optional
DEFAULT_SECURITY_GROUP_IDS=""       # comma-separated
DEFAULT_IAM_INSTANCE_PROFILE=""     # optional
START_INSTANCE_ON_LAUNCH="true"     # true = STARTED, false = STOPPED

# Operational
LOG_DIR="/tmp/mgn-migration-logs"
DRY_RUN="false"                     # set true or pass --dry-run
CONFIRM_PROMPTS="true"              # set false for fully automated runs

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${LOG_DIR}/mgn-advanced-${TIMESTAMP}.log"
REPORT_FILE="/tmp/mgn-wave-report-${TIMESTAMP}.json"

# =============================================================================
# HELPERS
# =============================================================================
log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" | tee -a "${LOG_FILE}"
}

die() { log "ERROR" "$*"; exit 1; }

confirm() {
    [[ "${CONFIRM_PROMPTS}" == "false" ]] && return 0
    read -r -p "$1 [y/N] " ans
    [[ "${ans}" =~ ^[Yy]$ ]] || die "Aborted by user"
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    command -v aws >/dev/null || die "AWS CLI required"
    command -v jq  >/dev/null || die "jq required"
    aws sts get-caller-identity --region "${AWS_REGION}" >/dev/null \
        || die "Invalid AWS credentials / region ${AWS_REGION}"
    mkdir -p "${LOG_DIR}"
    log "INFO" "Prerequisites OK → ${LOG_FILE}"
}

# -----------------------------------------------------------------------------
# BACKUP
# -----------------------------------------------------------------------------
perform_linux_backup() {
    local label="${1:-local}"
    local backup_name="linux-backup-${label}-${TIMESTAMP}"
    local local_dir="/tmp/${backup_name}"
    local s3_uri="s3://${S3_REPORT_BUCKET}/${BACKUP_S3_PREFIX}/${backup_name}"

    log "INFO" "Linux backup → ${s3_uri}"
    mkdir -p "${local_dir}"

    {
        echo "=== Host ==="; hostnamectl 2>/dev/null || hostname
        uname -a; df -h; free -h
        echo; echo "=== Packages ==="
        dpkg -l 2>/dev/null || rpm -qa 2>/dev/null || true
    } > "${local_dir}/system-info.txt"

    # Add application paths here if desired
    # tar -czf "${local_dir}/app.tar.gz" /opt/myapp || true

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would upload ${local_dir} → ${s3_uri}"
    else
        aws s3 sync "${local_dir}" "${s3_uri}/" --region "${AWS_REGION}"
    fi
    echo "${s3_uri}"
}

perform_windows_backup_guidance() {
    local ps1="/tmp/windows-pre-mgn-backup-${TIMESTAMP}.ps1"
    cat > "${ps1}" << 'EOF'
# Run as Administrator on the Windows source
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$root = "C:\MGN-PreMigration-Backup\$ts"
New-Item -ItemType Directory -Path $root -Force | Out-Null
systeminfo | Out-File "$root\systeminfo.txt"
Get-Volume | Format-List | Out-File "$root\volumes.txt"
Get-Service | Where Status -eq Running | Out-File "$root\services.txt"
Write-Host "Backup created at $root – upload to S3 if desired"
EOF
    log "INFO" "Windows backup helper written → ${ps1}"
    echo "${ps1}"
}

# -----------------------------------------------------------------------------
# WAVE MANAGEMENT
# -----------------------------------------------------------------------------
list_waves() {
    log "INFO" "Listing MGN Waves..."
    aws mgn list-waves --region "${AWS_REGION}" --output json \
        | jq -r '.items[] | "\(.waveID)\t\(.name)\t\(.isArchived)\t\(.waveAggregatedStatus.progressStatus // "N/A")"'
}

create_wave() {
    local name="$1"
    local desc="${2:-Created by advanced MGN migration script}"
    log "INFO" "Creating wave: ${name}"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would create wave ${name}"
        echo "wave-DRYRUN"
        return
    fi
    aws mgn create-wave \
        --region "${AWS_REGION}" \
        --name "${name}" \
        --description "${desc}" \
        --output json | jq -r '.waveID'
}

# Associate source servers to an application and then to a wave
# (Simplified – real-world often uses Applications as intermediate grouping)
associate_servers_to_wave() {
    local wave_id="$1"
    shift
    local server_ids=("$@")

    log "INFO" "Associating ${#server_ids[@]} server(s) with wave ${wave_id}"
    # Note: MGN prefers Application → Wave association.
    # For simplicity we tag servers and rely on wave-level operations where possible.
    # Full Application creation can be added if needed.
    for ssid in "${server_ids[@]}"; do
        aws mgn tag-resource \
            --region "${AWS_REGION}" \
            --resource-arn "arn:aws:mgn:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):source-server/${ssid}" \
            --tags "Key=MigrationWave,Value=${wave_id}" 2>/dev/null || true
    done
}

# -----------------------------------------------------------------------------
# RIGHT-SIZING + LAUNCH CONFIG
# -----------------------------------------------------------------------------
enable_right_sizing() {
    local ssid="$1"
    local method="NONE"
    [[ "${ENABLE_RIGHT_SIZING}" == "true" ]] && method="BASIC"

    log "INFO" "Setting right-sizing=${method} for ${ssid}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would update launch config for ${ssid}"
        return
    fi

    aws mgn update-launch-configuration \
        --region "${AWS_REGION}" \
        --source-server-id "${ssid}" \
        --target-instance-type-right-sizing-method "${method}" \
        --launch-disposition "$( [[ ${START_INSTANCE_ON_LAUNCH} == true ]] && echo STARTED || echo STOPPED )" \
        --copy-private-ip false \
        --copy-tags true \
        --enable-map-auto-tagging false \
        >/dev/null || log "WARN" "update-launch-configuration warning for ${ssid} (may already be set)"
}

# Optional heuristic override when right-sizing is off
suggest_instance_type() {
    local ssid="$1"
    # Pull source properties if available
    local cpus mem
    cpus=$(aws mgn describe-source-servers --region "${AWS_REGION}" \
        --filters "sourceServerIDs=${ssid}" --output json \
        | jq -r '.items[0].sourceProperties.cpus[0].cores // 2' 2>/dev/null || echo 2)
    mem=$(aws mgn describe-source-servers --region "${AWS_REGION}" \
        --filters "sourceServerIDs=${ssid}" --output json \
        | jq -r '.items[0].sourceProperties.ramBytes // 8589934592' 2>/dev/null || echo 8589934592)
    mem_gb=$(( mem / 1024 / 1024 / 1024 ))

    # Very simple mapping – expand as needed
    if (( cpus <= 2 && mem_gb <= 8 )); then echo "m5.large"
    elif (( cpus <= 4 && mem_gb <= 16 )); then echo "m5.xlarge"
    elif (( cpus <= 8 && mem_gb <= 32 )); then echo "m5.2xlarge"
    else echo "m5.4xlarge"
    fi
}

# -----------------------------------------------------------------------------
# TEST / CUTOVER
# -----------------------------------------------------------------------------
start_test_for_servers() {
    local -a ssids=("$@")
    log "INFO" "Starting TEST for ${#ssids[@]} server(s)"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would start-test on: ${ssids[*]}"
        echo "job-DRYRUN"
        return
    fi

    local job
    job=$(aws mgn start-test \
        --region "${AWS_REGION}" \
        --source-server-i-ds "${ssids[@]}" \
        --output json)
    echo "${job}" | jq -r '.job.jobID'
}

wait_for_job() {
    local job_id="$1"
    local timeout_min="${2:-90}"
    local end=$(( $(date +%s) + timeout_min * 60 ))

    [[ "${job_id}" == job-DRYRUN ]] && return 0

    log "INFO" "Waiting for job ${job_id} (max ${timeout_min} min)..."
    while true; do
        local status
        status=$(aws mgn describe-jobs --region "${AWS_REGION}" \
            --filters "jobIDs=${job_id}" --output json \
            | jq -r '.items[0].status // "UNKNOWN"')
        log "INFO" "  status = ${status}"
        case "${status}" in
            COMPLETED) return 0 ;;
            FAILED)    die "Job ${job_id} FAILED" ;;
        esac
        (( $(date +%s) > end )) && die "Timeout waiting for ${job_id}"
        sleep 30
    done
}

# -----------------------------------------------------------------------------
# REPORTING
# -----------------------------------------------------------------------------
generate_wave_report() {
    local wave_name="$1"
    local wave_id="$2"
    shift 2
    local -a ssids=("$@")
    local backup_loc="${BACKUP_LOCATION:-N/A}"
    local job_id="${LAST_JOB_ID:-N/A}"

    local servers_json="[]"
    for ssid in "${ssids[@]}"; do
        local detail
        detail=$(aws mgn describe-source-servers --region "${AWS_REGION}" \
            --filters "sourceServerIDs=${ssid}" --output json 2>/dev/null \
            | jq -c '.items[0] // {}' || echo '{}')
        servers_json=$(echo "${servers_json}" | jq --argjson s "${detail}" '. + [$s]')
    done

    local report
    report=$(jq -n \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg region "${AWS_REGION}" \
        --arg wname "${wave_name}" \
        --arg wid "${wave_id}" \
        --arg backup "${backup_loc}" \
        --arg job "${job_id}" \
        --argjson servers "${servers_json}" \
        --arg rightsizing "${ENABLE_RIGHT_SIZING}" \
        '{
            reportTimestamp: $ts,
            targetRegion: $region,
            waveName: $wname,
            waveID: $wid,
            rightSizingEnabled: ($rightsizing == "true"),
            preMigrationBackup: $backup,
            testJobID: $job,
            sourceServers: $servers,
            nextSteps: [
                "Validate test instances in EC2 / MGN console",
                "When ready: aws mgn start-cutover --source-server-i-ds <ids> --region '"${AWS_REGION}"'",
                "After cutover finalize and decommission source servers"
            ]
        }')

    echo "${report}" > "${REPORT_FILE}"
    local s3_key="${S3_REPORT_PREFIX}/wave-${wave_name}-${TIMESTAMP}.json"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY-RUN] Report would be uploaded to s3://${S3_REPORT_BUCKET}/${s3_key}"
    else
        aws s3 cp "${REPORT_FILE}" "s3://${S3_REPORT_BUCKET}/${s3_key}" --region "${AWS_REGION}"
        log "INFO" "Report uploaded → s3://${S3_REPORT_BUCKET}/${s3_key}"
    fi
    echo "s3://${S3_REPORT_BUCKET}/${s3_key}"
}

# =============================================================================
# MAIN
# =============================================================================
usage() {
    cat <<EOF
Advanced MGN Migration Script (Wave + Right-Sizing)

Usage:
  $0 [OPTIONS]

Core options:
  --wave-name NAME          Create / use a wave with this name
  --wave-id ID              Use an existing wave ID
  --server-ids id1,id2,...  Comma-separated source server IDs
  --os linux|windows        Backup method (default: linux)
  --list-waves              List existing waves and exit
  --list-servers            List source servers and exit
  --enable-right-sizing     Force BASIC right-sizing (default: on)
  --disable-right-sizing    Disable right-sizing (use DEFAULT_INSTANCE_TYPE)
  --dry-run                 Show what would happen without making changes
  --yes                     Skip confirmation prompts
  --help                    Show this help

Examples:
  # List everything
  $0 --list-waves
  $0 --list-servers

  # Process a new wave with three servers + automatic right-sizing
  $0 --wave-name "Wave-1-AppA" --server-ids s-aaa,s-bbb,s-ccc --os linux

  # Existing wave, dry-run
  $0 --wave-id wave-0123456789abcdef0 --server-ids s-aaa --dry-run

  # Disable right-sizing and force a specific size
  $0 --wave-name "Wave-DB" --server-ids s-db01 --disable-right-sizing
EOF
}

main() {
    local wave_name="" wave_id="" os_type="linux"
    local -a server_ids=()
    local list_waves_only=false list_servers_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --wave-name)          wave_name="$2"; shift 2 ;;
            --wave-id)            wave_id="$2"; shift 2 ;;
            --server-ids)         IFS=',' read -ra server_ids <<< "$2"; shift 2 ;;
            --os)                 os_type="$2"; shift 2 ;;
            --list-waves)         list_waves_only=true; shift ;;
            --list-servers)       list_servers_only=true; shift ;;
            --enable-right-sizing) ENABLE_RIGHT_SIZING="true"; shift ;;
            --disable-right-sizing) ENABLE_RIGHT_SIZING="false"; shift ;;
            --dry-run)            DRY_RUN="true"; shift ;;
            --yes)                CONFIRM_PROMPTS="false"; shift ;;
            --help|-h)            usage; exit 0 ;;
            *)                    die "Unknown option: $1" ;;
        esac
    done

    check_prerequisites

    if [[ "${list_waves_only}" == true ]]; then
        list_waves
        exit 0
    fi

    if [[ "${list_servers_only}" == true ]]; then
        aws mgn describe-source-servers --region "${AWS_REGION}" --output json \
            | jq -r '.items[] | "\(.sourceServerID)\t\(.lifeCycle.state)\t\(.dataReplicationInfo.dataReplicationState // "N/A")\t\(.sourceProperties.identificationHints.hostname // "?")"'
        exit 0
    fi

    [[ ${#server_ids[@]} -eq 0 ]] && die "Provide --server-ids"
    [[ -z "${wave_name}" && -z "${wave_id}" ]] && die "Provide --wave-name or --wave-id"

    # ------------------------------------------------------------------
    # 1. Wave handling
    # ------------------------------------------------------------------
    if [[ -z "${wave_id}" ]]; then
        confirm "Create new wave '${wave_name}'?"
        wave_id=$(create_wave "${wave_name}")
        log "INFO" "Wave created: ${wave_id}"
    else
        log "INFO" "Using existing wave: ${wave_id}"
    fi

    associate_servers_to_wave "${wave_id}" "${server_ids[@]}"

    # ------------------------------------------------------------------
    # 2. Backup
    # ------------------------------------------------------------------
    local BACKUP_LOCATION=""
    case "${os_type,,}" in
        linux)   BACKUP_LOCATION=$(perform_linux_backup "${wave_name:-wave}") ;;
        windows) BACKUP_LOCATION=$(perform_windows_backup_guidance) ;;
        *)       die "Unsupported --os value" ;;
    esac

    # ------------------------------------------------------------------
    # 3. Right-sizing + launch config for every server
    # ------------------------------------------------------------------
    for ssid in "${server_ids[@]}"; do
        enable_right_sizing "${ssid}"
        if [[ "${ENABLE_RIGHT_SIZING}" != "true" ]]; then
            local suggested
            suggested=$(suggest_instance_type "${ssid}")
            log "INFO" "Right-sizing disabled – suggested type for ${ssid}: ${suggested}"
        fi
    done

    # ------------------------------------------------------------------
    # 4. Start test instances (wave-level)
    # ------------------------------------------------------------------
    confirm "Launch TEST instances for ${#server_ids[@]} server(s) in wave ${wave_id}?"
    local LAST_JOB_ID
    LAST_JOB_ID=$(start_test_for_servers "${server_ids[@]}")
    log "INFO" "Test job ID: ${LAST_JOB_ID}"

    # Optional wait – comment out for fire-and-forget
    # wait_for_job "${LAST_JOB_ID}" 90

    # ------------------------------------------------------------------
    # 5. Report
    # ------------------------------------------------------------------
    local report_s3
    report_s3=$(generate_wave_report "${wave_name:-${wave_id}}" "${wave_id}" "${server_ids[@]}")

    log "INFO" "=============================================================="
    log "INFO" "Wave migration orchestration finished"
    log "INFO" "Wave          : ${wave_name} (${wave_id})"
    log "INFO" "Servers       : ${server_ids[*]}"
    log "INFO" "Right-sizing  : ${ENABLE_RIGHT_SIZING}"
    log "INFO" "Backup        : ${BACKUP_LOCATION}"
    log "INFO" "Test Job      : ${LAST_JOB_ID}"
    log "INFO" "Report (S3)   : ${report_s3}"
    log "INFO" "Next steps:"
    log "INFO" "  1. Validate test instances"
    log "INFO" "  2. When ready → aws mgn start-cutover --source-server-i-ds ${server_ids[*]} --region ${AWS_REGION}"
    log "INFO" "=============================================================="
}

main "$@"
