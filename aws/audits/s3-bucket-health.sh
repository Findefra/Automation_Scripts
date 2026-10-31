#!/usr/bin/env bash
# quarterly-s3-health.sh
# Checks versioning, encryption, public access block, logging, and lifecycle on every bucket.
# Real lesson: “Block Public Access” being on does not mean the bucket is safe. Policy and ACL drift still happen.
# Common mistake: Only checking the account-level BPA and ignoring bucket-level overrides or missing lifecycle rules.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/s3-health-$(date +%Y%m%d).csv"
echo "Bucket,Versioning,Encryption,PublicAccessBlock,Logging,Lifecycle,Issues" > "$REPORT"

aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read -r bucket; do
  issues=()

  # Versioning
  ver=$(aws s3api get-bucket-versioning --bucket "$bucket" --query 'Status' --output text 2>/dev/null || echo "None")
  [[ "$ver" != "Enabled" ]] && issues+=("VersioningNotEnabled")

  # Encryption
  enc=$(aws s3api get-bucket-encryption --bucket "$bucket" 2>/dev/null | jq -r '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' || echo "None")
  [[ "$enc" == "None" || -z "$enc" ]] && issues+=("NoDefaultEncryption")

  # Public Access Block
  pab=$(aws s3api get-public-access-block --bucket "$bucket" 2>/dev/null | jq -r '
    if .PublicAccessBlockConfiguration.BlockPublicAcls and
       .PublicAccessBlockConfiguration.IgnorePublicAcls and
       .PublicAccessBlockConfiguration.BlockPublicPolicy and
       .PublicAccessBlockConfiguration.RestrictPublicBuckets then "Full" else "Incomplete" end
  ' || echo "Missing")
  [[ "$pab" != "Full" ]] && issues+=("PublicAccessBlockIncomplete")

  # Logging
  log=$(aws s3api get-bucket-logging --bucket "$bucket" --query 'LoggingEnabled.TargetBucket' --output text 2>/dev/null || echo "None")
  [[ "$log" == "None" || -z "$log" ]] && issues+=("NoAccessLogging")

  # Lifecycle
  life=$(aws s3api get-bucket-lifecycle-configuration --bucket "$bucket" 2>/dev/null | jq -r '.Rules | length' || echo "0")
  [[ "$life" == "0" ]] && issues+=("NoLifecycleRules")

  issue_str=$(IFS=";"; echo "${issues[*]:-OK}")
  echo "$bucket,$ver,$enc,$pab,$log,$life,$issue_str" >> "$REPORT"
done

echo "S3 health report: $REPORT"
echo "Prioritize any bucket missing encryption or full Public Access Block."
