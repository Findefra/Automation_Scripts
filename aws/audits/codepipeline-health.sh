#!/usr/bin/env bash
# quarterly-codepipeline-health.sh
# Surfaces failed, stuck, and long-inactive pipelines.
# Real lesson: Pipelines that have not succeeded in 60–90 days are usually abandoned.
# Common mistake: Only looking at the last execution status and ignoring pipelines that are still “Enabled” but never run.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/codepipeline-health-$(date +%Y%m%d).csv"
echo "Region,PipelineName,LastExecutionStatus,LastExecutionTime,AgeDays,Trigger,Issues" > "$REPORT"
CUTOFF=$(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ)

for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  pipelines=$(aws codepipeline list-pipelines --region "$region" --query 'pipelines[].name' --output text 2>/dev/null || true)
  for pipe in $pipelines; do
    # Latest execution summary
    exec=$(aws codepipeline list-pipeline-executions --region "$region" --pipeline-name "$pipe" --max-items 1 --output json 2>/dev/null || echo "{}")
    
    status=$(echo "$exec" | jq -r '.pipelineExecutionSummaries[0].status // "NO_EXECUTIONS"')
    last_time=$(echo "$exec" | jq -r '.pipelineExecutionSummaries[0].startTime // "1970-01-01T00:00:00Z"')
    age_days=$(echo "$last_time" | jq -r --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      ((now | fromdateiso8601) - (fromdateiso8601)) / 86400 | floor
    ' 2>/dev/null || echo "9999")

    issues=()
    [[ "$status" == "Failed" ]] && issues+=("LastExecutionFailed")
    [[ "$status" == "InProgress" && "$age_days" -gt 1 ]] && issues+=("PossiblyStuck")
    [[ "$age_days" -gt 90 ]] && issues+=("NoSuccessIn90Days")
    [[ "$status" == "NO_EXECUTIONS" ]] && issues+=("NeverExecuted")

    issue_str=$(IFS=";"; echo "${issues[*]:-OK}")
    echo "$region,$pipe,$status,$last_time,$age_days,n/a,$issue_str" >> "$REPORT"
  done
done

echo "CodePipeline health report: $REPORT"
echo "Prioritize pipelines with NoSuccessIn90Days or LastExecutionFailed — most are safe to disable or delete after owner confirmation."
