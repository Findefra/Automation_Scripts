#!/usr/bin/env bash
# quarterly-unused-resources.sh
# Purpose: Surface orphaned cost drivers across all regions.
# Run with: AWS_PROFILE=prod ./quarterly-unused-resources.sh
# Real lesson: Always exclude known long-lived volumes (database data, etc.) via a tag or name pattern.

set -euo pipefail
export AWS_PAGER=""

REGIONS=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)
REPORT_DIR="./quarterly-reports/$(date +%Y-Q%q)"
mkdir -p "$REPORT_DIR"

echo "Region,ResourceType,ResourceId,SizeOrAge,NameOrTags,EstimatedMonthlyCostHint" > "$REPORT_DIR/unused.csv"

for region in $REGIONS; do
  echo "=== Scanning $region ===" >&2

  # Unattached EBS volumes older than 30 days
  aws ec2 describe-volumes --region "$region" \
    --filters Name=status,Values=available \
    --query 'Volumes[?CreateTime<=`'$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)'`].[VolumeId,Size,CreateTime,Tags]' \
    --output text | while read -r vol size created tags; do
      echo "$region,EBS-Unattached,$vol,${size}GB,$created,$tags,volume-cost" >> "$REPORT_DIR/unused.csv"
    done

  # Elastic IPs not associated
  aws ec2 describe-addresses --region "$region" \
    --query 'Addresses[?AssociationId==`null`].[PublicIp,AllocationId,Tags]' \
    --output text | while read -r ip alloc tags; do
      echo "$region,EIP-Unassociated,$ip,$alloc,$tags,~\$3.65/mo" >> "$REPORT_DIR/unused.csv"
    done

  # Old snapshots with no recent AMI reference (simplified – production version should check AMI associations)
  aws ec2 describe-snapshots --region "$region" --owner-ids self \
    --query 'Snapshots[?StartTime<=`'$(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ)'`].[SnapshotId,VolumeSize,StartTime,Description]' \
    --output text | while read -r snap size start desc; do
      echo "$region,Snapshot-Old,$snap,${size}GB,$start,$desc,snapshot-storage" >> "$REPORT_DIR/unused.csv"
    done
done

echo "Report written to $REPORT_DIR/unused.csv"
echo "Next action: Review, tag keepers with 'DoNotDelete=true', then delete the rest in a follow-up script."
