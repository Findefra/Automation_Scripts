#!/usr/bin/env bash
# =============================================================================
# create-svb-base-image-pipelines.sh
# Unified master script that creates EC2 Image Builder pipelines for:
#   - Windows Server
#   - Ubuntu
#   - Red Hat Enterprise Linux (RHEL)
#
# Naming convention : SVB_BaseImagePipeline_<OS>
# Default region    : us-west-2 (override with AWS_REGION)
# Schedule          : Biweekly (1st & 3rd Sunday) with dependency-update gate
#
# Prerequisites:
#   - AWS CLI v2 configured with permissions for imagebuilder, ec2, iam, ssm
#   - Instance profile that includes:
#       EC2InstanceProfileForImageBuilder + AmazonSSMManagedInstanceCore
#       (+ CloudWatchAgentServerPolicy recommended)
#   - Optional: custom component ARNs already published (see components/)
#
# Usage:
#   chmod +x create-svb-base-image-pipelines.sh
#   ./create-svb-base-image-pipelines.sh
#   ./create-svb-base-image-pipelines.sh --skip-shared   # skip infra/dist creation
#   ./create-svb-base-image-pipelines.sh --os windows    # only one OS
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration (override via environment)
# -----------------------------------------------------------------------------
REGION="${AWS_REGION:-us-west-2}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
INSTANCE_PROFILE_NAME="${INSTANCE_PROFILE_NAME:-EC2InstanceProfileForImageBuilder}"
INFRA_CONFIG_NAME="${INFRA_CONFIG_NAME:-SVB-ImageBuilder-InfraConfig}"
DIST_CONFIG_NAME="${DIST_CONFIG_NAME:-SVB-ImageBuilder-DistConfig}"
SEMANTIC_VERSION="${SEMANTIC_VERSION:-1.0.0}"
PROJECT_TAG="SVB"
MANAGED_BY_TAG="ImageBuilder"

# Parent images (versionless ARNs → always latest published by AWS)
WINDOWS_PARENT="arn:aws:imagebuilder:${REGION}:aws:image/windows-server-2022-english-full-base-x86/x.x.x"
UBUNTU_PARENT="arn:aws:imagebuilder:${REGION}:aws:image/ubuntu-server-24-lts-x86/x.x.x"
RHEL_PARENT="arn:aws:imagebuilder:${REGION}:aws:image/red-hat-enterprise-linux-9-x86/x.x.x"

# Optional custom component ARNs (set after publishing the YAML components)
CUSTOM_HARDENING_LINUX_ARN="${CUSTOM_HARDENING_LINUX_ARN:-}"
CUSTOM_HARDENING_WINDOWS_ARN="${CUSTOM_HARDENING_WINDOWS_ARN:-}"
CUSTOM_VULN_SCAN_ARN="${CUSTOM_VULN_SCAN_ARN:-}"

SKIP_SHARED=false
TARGET_OS="all"   # all | windows | ubuntu | rhel

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
log()  { echo -e "[\033[0;32mINFO\033[0m]  $*"; }
warn() { echo -e "[\033[0;33mWARN\033[0m]  $*"; }
die()  { echo -e "[\033[0;31mERROR\033[0m] $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --skip-shared     Do not create infrastructure / distribution configs
  --os <name>       Create only one OS pipeline (windows|ubuntu|rhel|all)
  -h, --help        Show this help
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-shared) SKIP_SHARED=true; shift ;;
    --os)          TARGET_OS="${2,,}"; shift 2 ;;
    -h|--help)     usage ;;
    *)             die "Unknown option: $1" ;;
  esac
done

# -----------------------------------------------------------------------------
# Shared resources
# -----------------------------------------------------------------------------
create_shared_resources() {
  log "Creating / ensuring shared Infrastructure Configuration: ${INFRA_CONFIG_NAME}"

  if aws imagebuilder get-infrastructure-configuration \
       --region "$REGION" \
       --infrastructure-configuration-arn \
       "arn:aws:imagebuilder:${REGION}:${ACCOUNT_ID}:infrastructure-configuration/${INFRA_CONFIG_NAME}" \
       &>/dev/null; then
    warn "Infrastructure configuration already exists – skipping create"
  else
    aws imagebuilder create-infrastructure-configuration \
      --region "$REGION" \
      --name "$INFRA_CONFIG_NAME" \
      --description "Shared infrastructure configuration for SVB base image pipelines" \
      --instance-types m5.large m5.xlarge m6i.large m6i.xlarge \
      --instance-profile-name "$INSTANCE_PROFILE_NAME" \
      --terminate-instance-on-failure \
      --tags "Project=${PROJECT_TAG},ManagedBy=${MANAGED_BY_TAG}" \
      --output text > /dev/null
    log "Infrastructure configuration created"
  fi

  log "Creating / ensuring shared Distribution Configuration: ${DIST_CONFIG_NAME}"

  if aws imagebuilder get-distribution-configuration \
       --region "$REGION" \
       --distribution-configuration-arn \
       "arn:aws:imagebuilder:${REGION}:${ACCOUNT_ID}:distribution-configuration/${DIST_CONFIG_NAME}" \
       &>/dev/null; then
    warn "Distribution configuration already exists – skipping create"
  else
    cat > /tmp/svb-dist-config.json <<EOF
{
  "name": "${DIST_CONFIG_NAME}",
  "description": "Distribute SVB golden AMIs",
  "distributions": [
    {
      "region": "${REGION}",
      "amiDistributionConfiguration": {
        "name": "SVB-{{imagebuilder:buildDate}}",
        "description": "SVB Base Image built {{imagebuilder:buildDate}}",
        "amiTags": {
          "Project": "${PROJECT_TAG}",
          "ManagedBy": "${MANAGED_BY_TAG}"
        }
      }
    }
  ]
}
EOF
    aws imagebuilder create-distribution-configuration \
      --region "$REGION" \
      --cli-input-json file:///tmp/svb-dist-config.json \
      --output text > /dev/null
    log "Distribution configuration created"
  fi
}

get_infra_arn() {
  aws imagebuilder list-infrastructure-configurations \
    --region "$REGION" \
    --query "infrastructureConfigurationSummaryList[?name=='${INFRA_CONFIG_NAME}'].arn" \
    --output text
}

get_dist_arn() {
  aws imagebuilder list-distribution-configurations \
    --region "$REGION" \
    --query "distributionConfigurationSummaryList[?name=='${DIST_CONFIG_NAME}'].arn" \
    --output text
}

# -----------------------------------------------------------------------------
# Recipe + Pipeline creation
# -----------------------------------------------------------------------------
create_recipe_and_pipeline() {
  local os="$1"
  local recipe_name="$2"
  local pipeline_name="$3"
  local parent_image="$4"
  local schedule_cron="$5"
  local platform="$6"   # Windows | Linux

  local components_json
  if [[ "$platform" == "Windows" ]]; then
    components_json=$(cat <<EOF
[
  {"componentArn": "arn:aws:imagebuilder:${REGION}:aws:component/update-windows/x.x.x"},
  {"componentArn": "arn:aws:imagebuilder:${REGION}:aws:component/amazon-cloudwatch-agent-windows/x.x.x"}
]
EOF
)
    if [[ -n "$CUSTOM_HARDENING_WINDOWS_ARN" ]]; then
      components_json=$(echo "$components_json" | jq --arg arn "$CUSTOM_HARDENING_WINDOWS_ARN" '. + [{"componentArn": $arn}]')
    fi
  else
    components_json=$(cat <<EOF
[
  {"componentArn": "arn:aws:imagebuilder:${REGION}:aws:component/update-linux/x.x.x"},
  {"componentArn": "arn:aws:imagebuilder:${REGION}:aws:component/amazon-cloudwatch-agent-linux/x.x.x"}
]
EOF
)
    if [[ -n "$CUSTOM_HARDENING_LINUX_ARN" ]]; then
      components_json=$(echo "$components_json" | jq --arg arn "$CUSTOM_HARDENING_LINUX_ARN" '. + [{"componentArn": $arn}]')
    fi
    if [[ -n "$CUSTOM_VULN_SCAN_ARN" ]]; then
      components_json=$(echo "$components_json" | jq --arg arn "$CUSTOM_VULN_SCAN_ARN" '. + [{"componentArn": $arn}]')
    fi
  fi

  log "Creating image recipe: ${recipe_name}"

  cat > /tmp/svb-recipe-${os}.json <<EOF
{
  "name": "${recipe_name}",
  "description": "SVB hardened ${os} base image – OS updates, CloudWatch agent, SSM retention, optional custom hardening",
  "semanticVersion": "${SEMANTIC_VERSION}",
  "parentImage": "${parent_image}",
  "components": ${components_json},
  "additionalInstanceConfiguration": {
    "systemsManagerAgent": {
      "uninstallAfterBuild": false
    }
  },
  "tags": {
    "Project": "${PROJECT_TAG}",
    "OS": "${os}",
    "ManagedBy": "${MANAGED_BY_TAG}"
  }
}
EOF

  local recipe_arn
  if recipe_arn=$(aws imagebuilder create-image-recipe \
        --region "$REGION" \
        --cli-input-json file:///tmp/svb-recipe-${os}.json \
        --query 'imageRecipeArn' --output text 2>/dev/null); then
    log "Recipe ARN: ${recipe_arn}"
  else
    # Recipe may already exist – fetch latest version ARN
    recipe_arn=$(aws imagebuilder list-image-recipes \
      --region "$REGION" \
      --query "imageRecipeSummaryList[?name=='${recipe_name}'].arn" \
      --output text | head -1)
    warn "Recipe already exists – using ${recipe_arn}"
  fi

  local infra_arn dist_arn
  infra_arn=$(get_infra_arn)
  dist_arn=$(get_dist_arn)
  [[ -n "$infra_arn" ]] || die "Infrastructure configuration ARN not found"
  [[ -n "$dist_arn" ]]  || die "Distribution configuration ARN not found"

  log "Creating image pipeline: ${pipeline_name}"

  cat > /tmp/svb-pipeline-${os}.json <<EOF
{
  "name": "${pipeline_name}",
  "description": "Biweekly SVB ${os} golden AMI pipeline – updates, logging, SSM, optional hardening/vuln scan",
  "imageRecipeArn": "${recipe_arn}",
  "infrastructureConfigurationArn": "${infra_arn}",
  "distributionConfigurationArn": "${dist_arn}",
  "enhancedImageMetadataEnabled": true,
  "imageTestsConfiguration": {
    "imageTestsEnabled": true,
    "timeoutMinutes": 90
  },
  "schedule": {
    "scheduleExpression": "${schedule_cron}",
    "pipelineExecutionStartCondition": "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE",
    "timezone": "UTC"
  },
  "status": "ENABLED",
  "tags": {
    "Project": "${PROJECT_TAG}",
    "OS": "${os}",
    "Schedule": "Biweekly",
    "ManagedBy": "${MANAGED_BY_TAG}"
  }
}
EOF

  local pipeline_arn
  if pipeline_arn=$(aws imagebuilder create-image-pipeline \
        --region "$REGION" \
        --cli-input-json file:///tmp/svb-pipeline-${os}.json \
        --query 'imagePipelineArn' --output text 2>/dev/null); then
    log "Pipeline ARN: ${pipeline_arn}"
  else
    pipeline_arn=$(aws imagebuilder list-image-pipelines \
      --region "$REGION" \
      --query "imagePipelineList[?name=='${pipeline_name}'].arn" \
      --output text | head -1)
    warn "Pipeline already exists – using ${pipeline_arn}"
  fi

  echo "  → Trigger manually: aws imagebuilder start-image-pipeline-execution --region ${REGION} --image-pipeline-arn ${pipeline_arn}"
  echo
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  log "Region          : ${REGION}"
  log "Account         : ${ACCOUNT_ID}"
  log "Instance profile: ${INSTANCE_PROFILE_NAME}"
  log "Target OS       : ${TARGET_OS}"
  echo

  if [[ "$SKIP_SHARED" == false ]]; then
    create_shared_resources
  else
    warn "Skipping shared resource creation (--skip-shared)"
  fi

  if [[ "$TARGET_OS" == "all" || "$TARGET_OS" == "windows" ]]; then
    create_recipe_and_pipeline \
      "WindowsServer" \
      "SVB_BaseImageRecipe_WindowsServer" \
      "SVB_BaseImagePipeline_WindowsServer" \
      "$WINDOWS_PARENT" \
      "cron(0 2 ? * SUN#1,SUN#3 *)" \
      "Windows"
  fi

  if [[ "$TARGET_OS" == "all" || "$TARGET_OS" == "ubuntu" ]]; then
    create_recipe_and_pipeline \
      "Ubuntu" \
      "SVB_BaseImageRecipe_Ubuntu" \
      "SVB_BaseImagePipeline_Ubuntu" \
      "$UBUNTU_PARENT" \
      "cron(0 3 ? * SUN#1,SUN#3 *)" \
      "Linux"
  fi

  if [[ "$TARGET_OS" == "all" || "$TARGET_OS" == "rhel" ]]; then
    create_recipe_and_pipeline \
      "RHEL" \
      "SVB_BaseImageRecipe_RHEL" \
      "SVB_BaseImagePipeline_RHEL" \
      "$RHEL_PARENT" \
      "cron(0 4 ? * SUN#1,SUN#3 *)" \
      "Linux"
  fi

  log "All requested pipelines processed successfully."
  log "Next steps:"
  echo "  1. Publish custom components from components/ (see README)"
  echo "  2. Set CUSTOM_*_ARN env vars and re-run to attach them to recipes"
  echo "  3. Trigger a pipeline or wait for the biweekly schedule"
}

main "$@"
