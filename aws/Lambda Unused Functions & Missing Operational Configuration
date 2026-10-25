#!/usr/bin/env bash
# quarterly-lambda-unused-and-config.sh
# Identifies functions with zero or near-zero invocations in the last 30 days and missing DLQ / tracing / insights.
# Real lesson: Unused functions still cost money (provisioned concurrency, excess versions, storage) and increase attack surface.
# Common mistake: Looking only at invocation count and ignoring that some functions are legitimately low-frequency (monthly jobs).

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/lambda-unused-config-$(date +%Y%m%d).csv"
echo "Region,FunctionName,Invocations30d,HasDLQ,Tracing,InsightsEnabled,LastModified,Issues" > "$REPORT"
START=$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)

for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  aws lambda list-functions --region "$region" --query 'Functions[].FunctionName' --output text 2>/dev/null | tr '\t' '\n' | while read -r fn; do
    [[ -z "$fn" ]] && continue

    # Invocation count (approximate via CloudWatch)
    invocations=$(aws cloudwatch get-metric-statistics --region "$region" \
      --namespace AWS/Lambda --metric-name Invocations \
      --dimensions Name=FunctionName,Value="$fn" \
      --start-time "$START" --end-time "$END" \
      --period 2592000 --statistics Sum \
      --query 'Datapoints[0].Sum' --output text 2>/dev/null || echo "0")
    invocations=${invocations%.*}  # strip decimal
    invocations=${invocations:-0}

    # Configuration
    config=$(aws lambda get-function-configuration --region "$region" --function-name "$fn" --output json 2>/dev/null || echo "{}")
    has_dlq=$(echo "$config" | jq -r 'if .DeadLetterConfig.TargetArn then "Yes" else "No" end')
    tracing=$(echo "$config" | jq -r '.TracingConfig.Mode // "PassThrough"')
    last_mod=$(echo "$config" | jq -r '.LastModified // "unknown"')

    # Lambda Insights (check for the layer)
    insights=$(echo "$config" | jq -r 'if any(.Layers[]?; .Arn | contains("LambdaInsightsExtension")) then "Yes" else "No" end')

    issues=()
    [[ "$invocations" -lt 5 ]] && issues+=("LowOrZeroInvocations")
    [[ "$has_dlq" == "No" ]] && issues+=("NoDLQ")
    [[ "$tracing" != "Active" ]] && issues+=("TracingNotActive")
    [[ "$insights" == "No" ]] && issues+=("NoLambdaInsights")

    issue_str=$(IFS=";"; echo "${issues[*]:-OK}")
    echo "$region,$fn,$invocations,$has_dlq,$tracing,$insights,$last_mod,$issue_str" >> "$REPORT"
  done
done

echo "Lambda unused / config report: $REPORT"
echo "LowOrZeroInvocations functions should be reviewed with the owner before deletion. Missing DLQ on critical functions is a reliability gap."
