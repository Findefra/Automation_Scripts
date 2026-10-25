#!/usr/bin/env bash
# quarterly-sso-assignments.sh
# Highlights permission sets with many assignments and provides a starting point for idle access review.
# Real lesson: The biggest SSO risk is not a single over-privileged user — it is the slow accumulation of assignments that no one reviews.
# Note: Full last-login data requires the Identity Store + CloudTrail or an external IdP report. This script focuses on assignment volume and structure.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/sso-assignments-$(date +%Y%m%d).csv"
echo "AccountId,PermissionSetArn,PermissionSetName,PrincipalType,PrincipalId,PrincipalName,Issues" > "$REPORT"

INSTANCE_ARN=$(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text)
IDENTITY_STORE_ID=$(aws sso-admin list-instances --query 'Instances[0].IdentityStoreId' --output text)

# Get all accounts in the org
accounts=$(aws organizations list-accounts --query 'Accounts[?Status==`ACTIVE`].Id' --output text)

for acct in $accounts; do
  # List all permission sets provisioned to this account
  ps_list=$(aws sso-admin list-permission-sets-provisioned-to-account \
    --instance-arn "$INSTANCE_ARN" --account-id "$acct" --query 'PermissionSets' --output text 2>/dev/null || true)

  for ps_arn in $ps_list; do
    ps_name=$(aws sso-admin describe-permission-set --instance-arn "$INSTANCE_ARN" --permission-set-arn "$ps_arn" --query 'PermissionSet.Name' --output text 2>/dev/null || echo "unknown")

    # Assignments for this account + permission set
    aws sso-admin list-account-assignments \
      --instance-arn "$INSTANCE_ARN" \
      --account-id "$acct" \
      --permission-set-arn "$ps_arn" \
      --output json 2>/dev/null | \
    jq -r --arg acct "$acct" --arg ps "$ps_arn" --arg name "$ps_name" '
      .AccountAssignments[] |
      [
        $acct,
        $ps,
        $name,
        .PrincipalType,
        .PrincipalId,
        "resolve-name-later",
        (if .PrincipalType == "USER" then "UserAssignment" else "GroupAssignment" end)
      ] | @csv
    ' >> "$REPORT" || true
  done
done

echo "SSO assignment inventory: $REPORT"
echo "Next step: Resolve PrincipalIds to names/emails via identitystore and cross-reference with HR leavers or last-activity data from your IdP."
