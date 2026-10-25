#!/usr/bin/env bash
# apply-imagebuilder-tf.sh
# Applies the Terraform Image Builder configuration safely.
# Real-world note: Always run plan first in CI. Never auto-apply Image Builder changes without human review of the recipe.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ENV="${ENVIRONMENT:-prod}"
TF_DIR="./imagebuilder-pipelines"

cd "$TF_DIR"

terraform init -upgrade
terraform plan \
  -var="region=$REGION" \
  -var="environment=$ENV" \
  -var="vpc_id=$VPC_ID" \
  -var="subnet_ids=[\"$SUBNET_ID\"]" \
  -var="security_group_ids=[\"$SG_ID\"]" \
  -out=tfplan

echo "Review the plan above. Re-run with 'apply' argument to execute."
if [[ "${1:-}" == "apply" ]]; then
  terraform apply tfplan
  echo "Image Builder pipelines applied."
fi
