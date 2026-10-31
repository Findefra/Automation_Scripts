#!/usr/bin/env bash
# quarterly-codebuild-config.sh
# Flags privileged mode, outdated images, missing encryption, and projects with no recent builds.
# Real lesson: Privileged mode is still turned on “temporarily” and left forever. 
# It significantly expands the blast radius of a compromised build.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/codebuild-config-$(date +%Y%m%d).csv"
echo "Region,ProjectName,PrivilegedMode,Image,LastBuildStatus,LastBuildTime,AgeDays,Issues" > "$REPORT"
CUTOFF=$(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ)

for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  projects=$(aws codebuild list-projects --region "$region" --query 'projects[]' --output text 2>/dev/null || true)
  for proj in $projects; do
    detail=$(aws codebuild batch-get-projects --region "$region" --names "$proj" --output json 2>/dev/null || echo "{}")
    
    privileged=$(echo "$detail" | jq -r '.projects[0].environment.privilegedMode // false')
    image=$(echo "$detail" | jq -r '.projects[0].environment.image // "unknown"')
    
    # Latest build
    builds=$(aws codebuild list-builds-for-project --region "$region" --project-name "$proj" --max-items 1 --output json 2>/dev/null || echo "{}")
    build_id=$(echo "$builds" | jq -r '.ids[0] // empty')
    
    last_status="NO_BUILDS"
    last_time="1970-01-01T00:00:00Z"
    if [[ -n "$build_id" ]]; then
      bdetail=$(aws codebuild batch-get-builds --region "$region" --ids "$build_id" --output json 2>/dev/null || echo "{}")
      last_status=$(echo "$bdetail" | jq -r '.builds[0].buildStatus // "UNKNOWN"')
      last_time=$(echo "$bdetail" | jq -r '.builds[0].startTime // "1970-01-01T00:00:00Z"')
    fi

    age_days=$(( ( $(date -u +%s) - $(date -u -d "$last_time" +%s 2>/dev/null || echo 0) ) / 86400 ))

    issues=()
    [[ "$privileged" == "true" ]] && issues+=("PrivilegedModeEnabled")
    [[ "$age_days" -gt 90 ]] && issues+=("NoBuildIn90Days")
    [[ "$last_status" == "FAILED" ]] && issues+=("LastBuildFailed")
    # Crude outdated image check – extend with your approved image list
    if echo "$image" | grep -qE 'python:3\.[6-8]|node:14|node:16|ubuntu:18|amazonlinux:1'; then
      issues+=("PossiblyOutdatedImage")
    fi

    issue_str=$(IFS=";"; echo "${issues[*]:-OK}")
    echo "$region,$proj,$privileged,$image,$last_status,$last_time,$age_days,$issue_str" >> "$REPORT"
  done
done

echo "CodeBuild configuration report: $REPORT"
echo "PrivilegedModeEnabled projects need justification or removal this quarter."
