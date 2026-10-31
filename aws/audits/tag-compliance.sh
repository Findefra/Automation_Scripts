#!/usr/bin/env bash
# quarterly-tag-compliance.sh
# Checks for required tags across EC2, RDS, S3, Lambda (extend as needed).
# Required tags example: Environment, Owner, CostCenter, Application

set -euo pipefail
REQUIRED_TAGS=("Environment" "Owner" "CostCenter" "Application")
REPORT="./quarterly-reports/tag-compliance-$(date +%Y%m%d).csv"
echo "Service,ResourceId,MissingTags,RegionOrGlobal" > "$REPORT"

# EC2 instances (example – expand to volumes, snapshots, etc.)
for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  aws ec2 describe-instances --region "$region" --query 'Reservations[].Instances[].[InstanceId,Tags]' --output json | \
  jq -r --arg region "$region" --argjson req "$(printf '%s\n' "${REQUIRED_TAGS[@]}" | jq -R . | jq -s .)" '
    .[] | select(length > 0) |
    . as $inst |
    ($inst[1] // []) | map(.Key) as $keys |
    ($req - $keys) as $missing |
    select(($missing | length) > 0) |
    ["EC2", $inst[0], ($missing | join(";")), $region] | @csv
  ' >> "$REPORT"
done

# S3 buckets (global)
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read -r bucket; do
  tags=$(aws s3api get-bucket-tagging --bucket "$bucket" 2>/dev/null | jq -r '.TagSet[].Key' || echo "")
  missing=""
  for t in "${REQUIRED_TAGS[@]}"; do
    echo "$tags" | grep -q "^$t$" || missing="$missing$t;"
  done
  if [[ -n "$missing" ]]; then
    echo "S3,$bucket,${missing%;},global" >> "$REPORT"
  fi
done

echo "Untagged / non-compliant resources: $REPORT"
