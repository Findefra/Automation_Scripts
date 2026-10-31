#!/usr/bin/env bash
# quarterly-ecr-repo-compliance.sh
# Checks for missing scan-on-push, overly permissive repository policies, and missing lifecycle policies.
# Real lesson: scan-on-push is free and still missing on a surprising number of repositories. 
# Lifecycle policies are the only reliable way to keep ECR costs under control long-term.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/ecr-repo-compliance-$(date +%Y%m%d).csv"
echo "Region,Repository,ScanOnPush,HasLifecyclePolicy,PolicyPrincipalWildcard,Issues" > "$REPORT"

for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  aws ecr describe-repositories --region "$region" --output json 2>/dev/null | \
  jq -r --arg region "$region" '
    .repositories[] |
    . as $r |
    [
      $region,
      $r.repositoryName,
      ($r.imageScanningConfiguration.scanOnPush // false),
      "check-later",
      "check-later",
      ""
    ] | @csv
  ' >> "$REPORT.tmp" || true
done

# Enrich with lifecycle and policy checks
while IFS=',' read -r region repo scan rest; do
  [[ "$region" == "Region" ]] && continue
  issues=()
  [[ "$scan" != "true" ]] && issues+=("ScanOnPushDisabled")

  # Lifecycle policy
  if ! aws ecr get-lifecycle-policy --region "$region" --repository-name "$repo" &>/dev/null; then
    issues+=("NoLifecyclePolicy")
  fi

  # Repository policy wildcard check (crude but effective)
  policy=$(aws ecr get-repository-policy --region "$region" --repository-name "$repo" 2>/dev/null || echo "")
  if echo "$policy" | grep -q '"Principal".*"[*]"'; then
    issues+=("PolicyAllowsPrincipalWildcard")
  fi

  issue_str=$(IFS=";"; echo "${issues[*]:-OK}")
  echo "$region,$repo,$scan,N/A,N/A,$issue_str" >> "$REPORT"
done < "$REPORT.tmp"
rm -f "$REPORT.tmp"

echo "ECR repository compliance: $REPORT"
echo "Any repo with ScanOnPushDisabled or NoLifecyclePolicy should be fixed this quarter."
