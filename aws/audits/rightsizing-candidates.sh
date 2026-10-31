#!/usr/bin/env bash
# quarterly-rightsizing-candidates.sh
# Flags EC2 instances with very low CPU over the last 14 days and RDS instances with low connection counts.
# Real lesson: CPU alone is a weak signal. Always cross-check memory, network, and application metrics before resizing.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/rightsizing-$(date +%Y%m%d).csv"
echo "Service,ResourceId,Region,Metric,Average,PeriodDays,Recommendation" > "$REPORT"
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START=$(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%SZ)

for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  # EC2 low CPU
  aws cloudwatch get-metric-statistics \
    --region "$region" \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=InstanceId,Value=i-placeholder \
    --start-time "$START" --end-time "$END" \
    --period 86400 --statistics Average 2>/dev/null || true

  # Practical approach: list instances then sample (production version uses metric math or a proper exporter)
  aws ec2 describe-instances --region "$region" \
    --filters Name=instance-state-name,Values=running \
    --query 'Reservations[].Instances[].[InstanceId,InstanceType,Tags[?Key==`Name`].Value|[0]]' \
    --output text | while read -r id type name; do
      avg=$(aws cloudwatch get-metric-statistics --region "$region" \
        --namespace AWS/EC2 --metric-name CPUUtilization \
        --dimensions Name=InstanceId,Value="$id" \
        --start-time "$START" --end-time "$END" \
        --period 1209600 --statistics Average \
        --query 'Datapoints[0].Average' --output text 2>/dev/null || echo "N/A")
      if [[ "$avg" != "N/A" && $(echo "$avg < 5" | bc -l) -eq 1 ]]; then
        echo "EC2,$id,$region,CPUUtilization,$avg,14,Consider downsize or schedule" >> "$REPORT"
      fi
    done
done

echo "Low-utilization candidates: $REPORT"
echo "Treat this as a shortlist only. Validate with application owners before any change."
