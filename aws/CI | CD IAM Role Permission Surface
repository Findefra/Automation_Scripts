#!/usr/bin/env bash
# quarterly-cicd-iam-roles.sh
# Finds IAM roles used by CodeBuild/CodePipeline that have AdministratorAccess or other high-risk managed policies.
# Real lesson: Most CI/CD roles start with PowerUser or Administrator “to unblock the pipeline” and never get tightened.
# This is one of the highest-value security findings you can produce in a quarterly review.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/cicd-iam-roles-$(date +%Y%m%d).csv"
echo "RoleName,RoleArn,TrustedService,AttachedHighRiskPolicies,Issues" > "$REPORT"

# High-risk managed policies we care about
HIGH_RISK="AdministratorAccess PowerUserAccess IAMFullAccess AmazonS3FullAccess"

aws iam list-roles --query 'Roles[?contains(RoleName, `codebuild`) || contains(RoleName, `codepipeline`) || contains(RoleName, `CodeBuild`) || contains(RoleName, `CodePipeline`)].RoleName' --output text | tr '\t' '\n' | while read -r role; do
  [[ -z "$role" ]] && continue

  arn=$(aws iam get-role --role-name "$role" --query 'Role.Arn' --output text)
  trust=$(aws iam get-role --role-name "$role" --query 'Role.AssumeRolePolicyDocument' --output json)

  # Check if it trusts codebuild or codepipeline
  trusts_cicd="No"
  echo "$trust" | grep -qE 'codebuild.amazonaws.com|codepipeline.amazonaws.com' && trusts_cicd="Yes"

  # Attached managed policies
  policies=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyName' --output text)
  
  high_risk_found=""
  for p in $HIGH_RISK; do
    if echo "$policies" | grep -q "$p"; then
      high_risk_found="$high_risk_found$p;"
    fi
  done

  issues=()
  [[ "$trusts_cicd" == "Yes" && -n "$high_risk_found" ]] && issues+=("HighRiskPolicyOnCICDRole")
  [[ "$trusts_cicd" == "Yes" && -z "$high_risk_found" ]] && issues+=("ReviewInlinePolicies")

  issue_str=$(IFS=";"; echo "${issues[*]:-OK}")
  echo "$role,$arn,$trusts_cicd,${high_risk_found%-},$issue_str" >> "$REPORT"
done

echo "CI/CD IAM role report: $REPORT"
echo "Any role with HighRiskPolicyOnCICDRole should be scheduled for least-privilege redesign this quarter."
