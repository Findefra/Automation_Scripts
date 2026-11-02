#!/usr/bin/env bash
# =============================================================================
# publish-svb-components.sh
# Uploads the custom SVB component YAML documents to S3 and registers them
# as EC2 Image Builder components (Linux + Windows hardening, Linux vuln scan).
#
# Prerequisites:
#   - S3 bucket for component storage (set COMPONENT_BUCKET)
#   - Permissions: s3:PutObject, imagebuilder:CreateComponent
#
# Usage:
#   export COMPONENT_BUCKET=my-imagebuilder-components-us-west-2
#   ./publish-svb-components.sh
# =============================================================================

set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
COMPONENT_BUCKET="${COMPONENT_BUCKET:?Set COMPONENT_BUCKET to an S3 bucket name}"
COMPONENT_PREFIX="${COMPONENT_PREFIX:-svb/components}"
SEMANTIC_VERSION="${SEMANTIC_VERSION:-1.0.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENTS_DIR="${SCRIPT_DIR}/components"

log()  { echo -e "[\033[0;32mINFO\033[0m]  $*"; }
die()  { echo -e "[\033[0;31mERROR\033[0m] $*" >&2; exit 1; }

publish_component() {
  local name="$1"
  local platform="$2"   # Linux | Windows
  local yaml_file="$3"
  local description="$4"

  local s3_uri="s3://${COMPONENT_BUCKET}/${COMPONENT_PREFIX}/$(basename "$yaml_file")"
  log "Uploading ${yaml_file} → ${s3_uri}"
  aws s3 cp "$yaml_file" "$s3_uri" --region "$REGION"

  log "Registering Image Builder component: ${name} (${platform})"

  cat > /tmp/create-component-${name}.json <<EOF
{
  "name": "${name}",
  "semanticVersion": "${SEMANTIC_VERSION}",
  "description": "${description}",
  "changeDescription": "Initial SVB component publish",
  "platform": "${platform}",
  "uri": "${s3_uri}",
  "tags": {
    "Project": "SVB",
    "ManagedBy": "ImageBuilder"
  }
}
EOF

  local arn
  if arn=$(aws imagebuilder create-component \
        --region "$REGION" \
        --cli-input-json file:///tmp/create-component-${name}.json \
        --query 'componentBuildVersionArn' --output text 2>/dev/null); then
    log "Created: ${arn}"
  else
    # May already exist – resolve latest
    arn=$(aws imagebuilder list-components \
      --region "$REGION" \
      --owner Self \
      --query "componentVersionList[?name=='${name}'].arn" \
      --output text | head -1)
    log "Component already exists – ARN: ${arn}"
  fi

  # Export for the master pipeline script
  case "$name" in
    SVB-Linux-Hardening)   echo "export CUSTOM_HARDENING_LINUX_ARN=\"${arn}\"" ;;
    SVB-Windows-Hardening) echo "export CUSTOM_HARDENING_WINDOWS_ARN=\"${arn}\"" ;;
    SVB-Linux-VulnScan)    echo "export CUSTOM_VULN_SCAN_ARN=\"${arn}\"" ;;
  esac
}

main() {
  [[ -d "$COMPONENTS_DIR" ]] || die "Components directory not found: $COMPONENTS_DIR"

  log "Region : ${REGION}"
  log "Bucket : ${COMPONENT_BUCKET}"
  log "Prefix : ${COMPONENT_PREFIX}"
  echo

  publish_component \
    "SVB-Linux-Hardening" \
    "Linux" \
    "${COMPONENTS_DIR}/svb-linux-hardening.yaml" \
    "SVB extra Linux hardening (SSH, sysctl, auditd, chrony)"

  publish_component \
    "SVB-Windows-Hardening" \
    "Windows" \
    "${COMPONENTS_DIR}/svb-windows-hardening.yaml" \
    "SVB extra Windows hardening (SMBv1, password policy, firewall, audit)"

  publish_component \
    "SVB-Linux-VulnScan" \
    "Linux" \
    "${COMPONENTS_DIR}/svb-linux-vuln-scan.yaml" \
    "SVB Linux package inventory and lightweight vulnerability surface scan"

  echo
  log "All components published. Source the export lines above or set the CUSTOM_*_ARN variables, then re-run the master pipeline script."
}

main "$@"
