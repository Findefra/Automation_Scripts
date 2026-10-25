#!/usr/bin/env bash
# quarterly-sso-permission-sets.sh
# Inventory of permission sets, their assigned accounts/users/groups, and high-risk managed policies.
# Real lesson: Permission sets accumulate. Teams request “temporary” AdministratorAccess sets that become permanent.
# Common mistake: Only looking at permission sets and ignoring the actual account assignments — unused assignments are pure risk.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/sso-permission-sets-$(date +%Y%m%d).csv"
echo "PermissionSetArn,PermissionSetName,SessionDuration,ManagedPolicies,AssignedAccounts,AssignedPrincipals,Issues" > "$REPORT"

# Get Identity Store and Instance ARN (adjust if you have multiple)
INSTANCE_ARN=$(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text)
IDENTITY_STORE_ID=$(aws sso-admin list-instances --query 'Instances[0].IdentityStoreId' --output text)

aws sso-admin list-permission-sets --instance-arn "$INSTANCE_ARN" --output json | \
jq -r '.PermissionSets[]' | while read -r ps_arn; do
  detail=$(aws sso-admin describe-permission-set --instance-arn "$INSTANCE_ARN" --permission-set-arn "$ps_arn" --output json)
  name=$(echo "$detail" | jq -r '.PermissionSet.Name')
  duration=$(echo "$detail" | jq -r '.PermissionSet.SessionDuration // "PT1H"')

  # Managed policies attached to the permission set
  policies=$(aws sso-admin list-managed-policies-in-permission-set \
    --instance-arn "$INSTANCE_ARN" --permission-set-arn "$ps_arn" \
    --query 'AttachedManagedPolicies[].Name' --output text 2>/dev/null || echo "")

  # Account assignments
  accounts=$(aws sso-admin list-accounts-for-provisioned-permission-set \
    --instance-arn "$INSTANCE_ARN" --permission-set-arn "$ps_arn" \
    --query 'AccountIds' --output text 2>/dev/null || echo "")

  # Rough principal count (users + groups) – detailed expansion is expensive
  principal_count=$(aws sso-admin list-account-assignments \
    --instance-arn "$INSTANCE_ARN" --account-id "$(echo $accounts | awk '{print $1}')" \
    --permission-set-arn "$ps_arn" --query 'length(AccountAssignments)' --output text 2>/dev/null || echo "0")

  issues=()
  if echo "$policies" | grep -qE 'AdministratorAccess|PowerUserAccess|IAMFullAccess'; then
    issues+=("HighRiskManagedPolicy")
  fi
  [[ -z "$accounts" || "$accounts" == "None" ]] && issues+=("NoAccountAssignments")
  [[ "$duration" == "PT12H" || "$duration" == "PT8H" ]] && issues+=("LongSessionDuration")

  issue_str=$(IFS=";"; echo "${issues[*]:-OK}")
  echo "$ps_arn,$name,$duration,$policies,${accounts// /;},$principal_count,$issue_str" >> "$REPORT"
done

echo "SSO permission set report: $REPORT"
echo "Any permission set with HighRiskManagedPolicy needs justification or replacement with a tighter set this quarter."
