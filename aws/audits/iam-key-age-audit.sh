#!/usr/bin/env bash
# quarterly-iam-key-age.sh
# Surfaces access keys older than 90 days and console users who have never logged in or have stale passwords.
# Real lesson: Never auto-disable keys without a grace period and owner notification. You will break CI pipelines.

set -euo pipefail
export AWS_PAGER=""

CUTOFF=$(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ)
REPORT="./quarterly-reports/iam-key-age-$(date +%Y%m%d).csv"

echo "UserName,KeyId,CreateDate,LastUsed,Status,AgeDays,ActionRecommended" > "$REPORT"

aws iam list-users --query 'Users[].UserName' --output text | tr '\t' '\n' | while read -r user; do
  aws iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[]' --output json | \
  jq -r --arg cutoff "$CUTOFF" --arg user "$user" '
    .[] | select(.CreateDate < $cutoff) |
    [$user, .AccessKeyId, .CreateDate, (.Status // "Unknown"), "ROTATE_OR_DELETE"] | @csv
  ' >> "$REPORT" || true

  # Console last login (requires GetLoginProfile which fails for users without console access)
  if aws iam get-login-profile --user-name "$user" &>/dev/null; then
    # You still need CloudTrail or Credential Report for true last-used; this is a starting point
    echo "$user,CONSOLE,N/A,N/A,HasConsolePassword,CHECK_CREDENTIAL_REPORT" >> "$REPORT"
  fi
done

echo "Report: $REPORT"
echo "Follow-up: Generate the official Credential Report (aws iam generate-credential-report) and merge."
