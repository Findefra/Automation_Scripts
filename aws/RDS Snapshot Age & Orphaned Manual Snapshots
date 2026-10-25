#!/usr/bin/env bash
# quarterly-rds-snapshots.sh
# Lists manual snapshots older than 90 days and automated snapshots that may be lingering.
# Real lesson: Manual snapshots created “just in case” before a big change are almost never cleaned up.

set -euo pipefail
export AWS_PAGER=""
REPORT="./quarterly-reports/rds-snapshots-$(date +%Y%m%d).csv"
echo "Region,SnapshotId,DBInstanceOrCluster,Type,CreateTime,AgeDays,Status,Encrypted" > "$REPORT"
CUTOFF=$(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ)

for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  aws rds describe-db-snapshots --region "$region" --snapshot-type manual --output json 2>/dev/null | \
  jq -r --arg region "$region" --arg cutoff "$CUTOFF" '
    .DBSnapshots[] | select(.SnapshotCreateTime < $cutoff) |
    [
      $region,
      .DBSnapshotIdentifier,
      .DBInstanceIdentifier,
      "manual",
      .SnapshotCreateTime,
      ((now - (.SnapshotCreateTime | fromdateiso8601)) / 86400 | floor),
      .Status,
      .Encrypted
    ] | @csv
  ' >> "$REPORT" || true
done

echo "Old manual RDS snapshots: $REPORT"
echo "Review with the application owners before deletion — some are kept for compliance."
