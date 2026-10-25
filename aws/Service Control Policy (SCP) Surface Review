#!/usr/bin/env bash
# quarterly-org-scps.sh
# Lists all SCPs, their targets, and flags potentially dangerous or missing guardrails.
# Real lesson: The most common SCP failure mode is not a bad policy — it is the absence of expected guardrails on production OUs.
# Second most common: an SCP that was attached for a one-time exception and never removed.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/org-scps-$(date +%Y%m%d).csv"
echo "PolicyId,PolicyName,Type,AwsManaged,AttachedTargets,Issues" > "$REPORT"

# List all policies
aws organizations list-policies --filter SERVICE_CONTROL_POLICY --output json | \
jq -r '.Policies[] | [.Id, .Name, .Type, .AwsManaged] | @csv' > /tmp/scp-list.csv

while IFS=',' read -r id name type managed; do
  id=$(echo "$id" | tr -d '"')
  name=$(echo "$name" | tr -d '"')
  managed=$(echo "$managed" | tr -d '"')

  # Targets
  targets=$(aws organizations list-targets-for-policy --policy-id "$id" --output json 2>/dev/null | \
    jq -r '[.Targets[].TargetId] | join(";")' || echo "none")

  issues=()
  [[ "$managed" == "true" ]] && issues+=("AWSManaged")
  [[ "$targets" == "none" || -z "$targets" ]] && issues+=("NotAttached")
  # Crude content checks – extend with your required guardrails
  content=$(aws organizations describe-policy --policy-id "$id" --query 'Policy.Content' --output text 2>/dev/null || echo "")
  if echo "$content" | grep -q 'Action.*\*'; then
    issues+=("ContainsWildcardAction")
  fi
  if echo "$content" | grep -q 'NotAction'; then
    issues+=("UsesNotAction")
  fi

  issue_str=$(IFS=";"; echo "${issues[*]:-OK}")
  echo "$id,$name,$type,$managed,$targets,$issue_str" >> "$REPORT"
done < /tmp/scp-list.csv
rm -f /tmp/scp-list.csv

echo "SCP review: $REPORT"
echo "Review any policy with ContainsWildcardAction or NotAttached. Confirm production OUs still have the expected deny guardrails."
